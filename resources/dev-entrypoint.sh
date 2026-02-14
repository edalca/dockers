#!/bin/bash

# ==============================================================================
# Development Entrypoint for Frappe/ERPNext
# Handles bind-mounted apps, dynamic installation, and environment linking.
# ==============================================================================

# Exit immediately on error
set -e
set -o pipefail

# ------------------------------------------------------------------------------
# Configuration & Defaults
# ------------------------------------------------------------------------------
APPS_DIR="/home/frappe/frappe-bench/apps"
BENCH_DIR="/home/frappe/frappe-bench"
PIP_BIN="pip3"

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S')] ℹ️  $1"
}

warn() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S')] ⚠️  $1" >&2
}

error() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S')] ❌ ERROR: $1" >&2
    exit 1
}

wait_for_service() {
    local host=$1
    local port=$2
    local name=$3
    local timeout=${4:-60}
    
    log "Waiting for service: $name ($host:$port)..."
    if command -v wait-for-it &> /dev/null; then
        wait-for-it -t "$timeout" "$host:$port"
    else
        timeout "$timeout" bash -c "until >/dev/tcp/$host/$port; do sleep 1; done" || error "Timeout waiting for $name"
    fi
    log "Service $name is ready."
}

# ------------------------------------------------------------------------------
# 1. App Installation & Restoration
# ------------------------------------------------------------------------------
log "🚀 Starting Development Entrypoint..."

if [ -n "$FRAPPE_APPS" ]; then
    log "🔍 Processing FRAPPE_APPS environment variable..."
    
    # helper function to validate base64
    validate_json() {
        echo "$1" | jq . >/dev/null 2>&1
    }

    # Decode payload
    DECODED_APPS=$(echo "$FRAPPE_APPS" | base64 -d)
    
    if validate_json "$DECODED_APPS"; then
        # Parse passing to a temporary loop
        # We use jq to handle the array iteration
        count=$(echo "$DECODED_APPS" | jq '. | length')
        
        for (( i=0; i<$count; i++ )); do
            row=$(echo "$DECODED_APPS" | jq -r ".[$i] | @base64")
            
            # Function to decode inner json object
            _jq() {
             echo "${row}" | base64 -d | jq -r "${1}"
            }
            
            url=$(_jq '.url')
            branch=$(_jq '.branch')
            
            # Handle potential nulls
            if [ "$branch" == "null" ]; then branch=""; fi
            
            # clean url to get app name
            repo_name=$(basename "$url" .git)
            
            if [ -d "$APPS_DIR/$repo_name" ]; then
                log "✅ App '$repo_name' already exists in apps volume."
            else
                log "⬇️  App '$repo_name' missing. Cloning from $url..."
                if [ -n "$branch" ]; then
                    bench get-app --branch "$branch" --resolve-deps "$repo_name" "$url"
                else
                    bench get-app --resolve-deps "$repo_name" "$url"
                fi
            fi
        done
    else
        error "FRAPPE_APPS is not a valid JSON. Please check the format."
    fi
fi

# ------------------------------------------------------------------------------
# 2. Python Environment & Re-linking
# ------------------------------------------------------------------------------
# Because we are in dev with bind-mounts, the local python env might lose track 
# of installed packages if the container is recreated but the volume persists,
# or if new apps were added. We force re-link everything.

log "🔗 Re-linking apps to Python environment..."
cd "$BENCH_DIR"

# A. Install 'frappe' first (CORE REQUIREMENT)
if [ -d "apps/frappe" ]; then
    log "   -> Linking core: frappe"
    "$PIP_BIN" install -q -e apps/frappe --no-cache-dir
else
    error "Frappe app not found in apps/frappe! Critical error."
fi

# B. Install all other apps
for app_path in apps/*; do
    if [ -d "$app_path" ]; then
        app_name=$(basename "$app_path")
        
        # Skip frappe as it's already done
        if [ "$app_name" == "frappe" ]; then continue; fi
        
        log "   -> Linking app: $app_name"
        "$PIP_BIN" install -q -e "$app_path" --no-deps
        
        # Install requirements if present
        if [ -f "$app_path/requirements.txt" ]; then
            log "      -> Installing requirements.txt for $app_name"
            "$PIP_BIN" install -q -r "$app_path/requirements.txt"
        fi
    fi
done

# ------------------------------------------------------------------------------
# 3. Site Configuration & Asset Management
# ------------------------------------------------------------------------------

# Re-build apps.txt based on actual directories
# This ensures benchmarks knows about all apps
ls -1 apps > sites/apps.txt
log "📝 Updated sites/apps.txt"

# Configure global basics
bench set-config -g db_host "${DB_HOST:-db}"
bench set-config -gp db_port "${DB_PORT:-3306}"
bench set-config -g redis_cache "redis://${REDIS_CACHE:-redis:6379/0}"
bench set-config -g redis_queue "redis://${REDIS_QUEUE:-redis:6379/1}"
bench set-config -g redis_socketio "redis://${REDIS_SOCKETIO:-redis:6379/2}"
bench set-config -gp socketio_port "${SOCKETIO_PORT:-9000}"
bench set-config -g developer_mode 1

# Only build if we are NOT running the 'watch' command, roughly
# (Or we can just rely on the user to run bench build if assets are missing, 
# but in dev it's nice to ensure symlinks are there)
log "📦 Ensuring assets are symlinked..."
bench build --restore

# ------------------------------------------------------------------------------
# 4. Wait for Dependencies
# ------------------------------------------------------------------------------
wait_for_service "${DB_HOST:-db}" "${DB_PORT:-3306}" "MariaDB"

# ------------------------------------------------------------------------------
# 5. Site Creation / Migration
# ------------------------------------------------------------------------------
if [ -n "$SITE_NAME" ]; then
    if [ ! -d "sites/$SITE_NAME" ]; then
        log "🏗️  Creating new site: $SITE_NAME..."
        
        # Build install-app args from all apps found in apps/ folder
        # standard for dev: install everything you have
        INSTALL_ARGS=""
        for app in apps/*; do
             app_name=$(basename "$app")
             if [ "$app_name" != "frappe" ]; then
                 INSTALL_ARGS="$INSTALL_ARGS --install-app $app_name"
             fi
        done

        bench new-site "$SITE_NAME" \
            --no-mariadb-socket \
            --mariadb-user-host-login-scope='%' \
            --admin-password "${ADMIN_PASSWORD:-admin}" \
            --db-root-username=root \
            --db-root-password "$DB_ROOT_PASSWORD" \
            $INSTALL_ARGS \
            --set-default
            
        log "✅ Site $SITE_NAME created."
    else
        log "✅ Site $SITE_NAME exists."
        bench use "$SITE_NAME"
        
        log "🔄 Running migrations..."
        bench migrate
    fi
fi

# ------------------------------------------------------------------------------
# 6. Handover
# ------------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    log "🚀 Executing command: $@"
    exec "$@"
else
    log "⚠️  No command (sleeping)..."
    exec sleep infinity
fi