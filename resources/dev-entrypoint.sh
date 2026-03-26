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

for app in /home/frappe/frappe-bench/apps/*; do
    if [ -d "$app" ]; then
        app_name=$(basename "$app")
        log "📦 Installing app in editable mode: $app_name..."
        bench pip install -e "$app"
    fi
done


# ------------------------------------------------------------------------------
# 2. Site Configuration (Prioritized)
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

# ------------------------------------------------------------------------------
# 3. Wait for Dependencies
# ------------------------------------------------------------------------------
wait_for_service "${DB_HOST:-db}" "${DB_PORT:-3306}" "MariaDB"

# ------------------------------------------------------------------------------
# 4. Site Creation (Prioritized)
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
       
    fi
fi
 # ------------------------------------------------------------------------------
        # 5. Migrations (Optional)
        # ------------------------------------------------------------------------------
if [ -z "$SKIP_MIGRATE" ]; then
    log "🔄 Running migrations..."
    bench migrate
else
    log "⏩ Skipping migrations (SKIP_MIGRATE is set)"
fi
# ------------------------------------------------------------------------------
# 6. Asset Management (Optional, at End)
# ------------------------------------------------------------------------------
# Only build if we are NOT running the 'watch' command, roughly
# (Or we can just rely on the user to run bench build if assets are missing, 
# but in dev it's nice to ensure symlinks are there)
if [ -z "$SKIP_BUILD" ]; then
    log "📦 Ensuring assets are symlinked..."
    bench build
else
    log "⏩ Skipping asset build (SKIP_BUILD is set)"
fi

# ------------------------------------------------------------------------------
# 7. Handover
# ------------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    log "🚀 Executing command: $@"
    exec "$@"
else
    log "⚠️  No command (sleeping)..."
    exec sleep infinity
fi