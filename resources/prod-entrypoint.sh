#!/bin/bash

# ==============================================================================
# Production Entrypoint for Frappe/ERPNext
# Optimized for reliability, observability, and fail-fast behavior.
# ==============================================================================

# Exit immediately on error, treat unset variables as an error (optional, but good for strictness),
# and fail if any command in a pipe fails.
set -e
set -o pipefail

# ------------------------------------------------------------------------------
# Configuration & Defaults
# ------------------------------------------------------------------------------
SOCKETIO_PORT=${SOCKETIO_PORT:-9000}
HTTP_TIMEOUT=${HTTP_TIMEOUT:-60}
# Default CORS to the specific domain if not provided (preserving original behavior)
# ALLOW_CORS is now optional and has no default
ALLOW_CORS=${ALLOW_CORS}

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

# Log with timestamp for better observability in production logs
log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ℹ️  $1"
}

warn() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ⚠️  $1" >&2
}

error() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ❌ ERROR: $1" >&2
    exit 1
}

# Check for required environment variables to fail fast
check_required_env() {
    local missing=0
    # INSTALL_APPS is optional, but if SITE_NAME is present, we likely want apps.
    local required_vars=("DB_HOST" "DB_PORT" "REDIS_CACHE" "REDIS_QUEUE" "SITE_NAME" "ADMIN_PASSWORD" "DB_ROOT_PASSWORD")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            warn "Missing required environment variable: $var"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        error "Cannot proceed without required environment variables."
    fi
}

# Robust service waiter
wait_for_service() {
    local host=$1
    local port=$2
    local name=$3
    
    log "Waiting for service: $name ($host:$port)..."
    
    # Try using wait-for-it if available
    if command -v wait-for-it &> /dev/null; then
        wait-for-it -t "$HTTP_TIMEOUT" "$host:$port"
    else
        # Fallback to bash built-in tcp check
        local start_ts=$(date +%s)
        while :; do
            if (echo > /dev/tcp/$host/$port) >/dev/null 2>&1; then
                break
            fi
            local current_ts=$(date +%s)
            if [ $((current_ts - start_ts)) -ge "$HTTP_TIMEOUT" ]; then
                error "Timeout waiting for $name at $host:$port"
            fi
            sleep 1
        done
    fi
    log "Service $name is ready."
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------

log "Starting production entrypoint..."

# 1. Validation
check_required_env

# 2. Extract Parsed Redis Hosts (handling simple hostname or URI format if complex)
# Assuming format is host:port based on original script usage
R_HOST=$(echo $REDIS_CACHE | cut -d: -f1)
R_PORT=$(echo $REDIS_CACHE | cut -d: -f2)
Q_HOST=$(echo $REDIS_QUEUE | cut -d: -f1)
Q_PORT=$(echo $REDIS_QUEUE | cut -d: -f2)

# 3. Wait for Dependencies
wait_for_service "$DB_HOST" "$DB_PORT" "MariaDB"
wait_for_service "$R_HOST" "$R_PORT" "Redis Cache"
wait_for_service "$Q_HOST" "$Q_PORT" "Redis Queue"

# 4. Global Configuration (common_site_config.json)
log "Configuring global settings..."

# Generate apps.txt (crucial for Frappe to know which apps are installed)
ls -1 apps > sites/apps.txt

# Configure bench global settings
bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g redis_cache "redis://$REDIS_CACHE"
bench set-config -g redis_queue "redis://$REDIS_QUEUE"
bench set-config -g redis_socketio "redis://$REDIS_QUEUE"
bench set-config -gp socketio_port "$SOCKETIO_PORT"

if [ -n "$ALLOW_CORS" ]; then
    bench set-config -g allow_cors "$ALLOW_CORS"
fi

# 5. Site Management (Create or Migrate)
SITE_DIR="sites/$SITE_NAME"
SITE_CONFIG="$SITE_DIR/site_config.json"

if [ ! -f "$SITE_CONFIG" ]; then
    log "Site '$SITE_NAME' not found (no site_config.json). Creating new site..."
    
    # Prepare install-app arguments
    INSTALL_ARGS=""
    if [ -n "$INSTALL_APPS" ]; then
        IFS=',' read -ra ADDR <<< "$INSTALL_APPS"
        for app in "${ADDR[@]}"; do
            # trim whitespace
            app=$(echo "$app" | xargs)
            if [ -n "$app" ]; then
                if [ -d "apps/$app" ]; then
                    log "App '$app' found locally. Adding to install list."
                    INSTALL_ARGS="$INSTALL_ARGS --install-app $app"
                else
                    warn "App '$app' specified in INSTALL_APPS but not found in 'apps/' directory. Skipping."
                fi
            fi
        done
    fi

    # new-site command
    bench new-site "$SITE_NAME" \
        --no-mariadb-socket \
        --mariadb-user-host-login-scope='%' \
        --admin-password="$ADMIN_PASSWORD" \
        --db-root-username=root \
        --db-root-password="$DB_ROOT_PASSWORD" \
        $INSTALL_ARGS \
        --set-default \
        --verbose
        
    log "Site '$SITE_NAME' created successfully."
else
    log "Site '$SITE_NAME' implies existing site."
    
    log "Running migrations..."
    # Check if we should enforce maintenance mode (safer for prod migrations)
    # Using '|| true' to prevent crash if site is already in that state or command fails harmlessly
    bench --site "$SITE_NAME" set-maintenance-mode on || true
    
    bench --site "$SITE_NAME" migrate
    
    if [ -n "$INSTALL_APPS" ]; then
        log "Verifying installation of apps: $INSTALL_APPS"
        IFS=',' read -ra ADDR <<< "$INSTALL_APPS"
        for app in "${ADDR[@]}"; do
            app=$(echo "$app" | xargs)
            if [ -n "$app" ]; then
                if [ -d "apps/$app" ]; then
                    if ! bench --site "$SITE_NAME" list-apps | grep -q "$app"; then
                        log "App '$app' missing from site. Attempting install..."
                        bench --site "$SITE_NAME" install-app "$app"
                    fi
                else
                     warn "App '$app' specified in INSTALL_APPS but not found in 'apps/' directory. Cannot install."
                fi
            fi
        done
    fi
    
    bench --site "$SITE_NAME" set-maintenance-mode off || true
    log "Migration and setup completed."
fi

# 6. Handover to Command
if [ $# -gt 0 ]; then
    log "Executing command: $*"
    exec "$@"
else
    log "No command provided. Sleeping infinity..."
    exec sleep infinity
fi