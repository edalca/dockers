#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "🚀 Starting Frappe Environment..."

APPS_DIR="/home/frappe/frappe-bench/apps"
BENCH_DIR="/home/frappe/frappe-bench"

# ------------------------------------------------------------
# 1. Download apps defined in FRAPPE_APPS (Base64 JSON)
# ------------------------------------------------------------
if [ -n "$FRAPPE_APPS" ]; then
    echo "🔍 Checking for apps defined in FRAPPE_APPS..."
    
    # Decode Base64 and parse JSON length using jq
    raw_json=$(echo "$FRAPPE_APPS" | base64 -d)
    count=$(echo "$raw_json" | jq '. | length')

    for (( i=0; i<$count; i++ )); do
        url=$(echo "$raw_json" | jq -r ".[$i].url")
        branch=$(echo "$raw_json" | jq -r ".[$i].branch")
        repo_name=$(basename "$url" .git)

        # Download app only if the directory does not exist
        if [ ! -d "$APPS_DIR/$repo_name" ]; then
            echo "⬇️  Installing app from $url..."
            bench get-app --branch "$branch" "$url"
        else
            echo "✅ Repo '$repo_name' already present."
        fi
    done
else
    echo "ℹ️  No FRAPPE_APPS defined. Using base Frappe only."
fi

# ------------------------------------------------------------
# 2. Re-link apps to Python environment (REDEPLOY FIX)
# ------------------------------------------------------------
# This step is critical because the virtual environment (env) is inside 
# the container, while the apps are in a persistent volume.
echo "🔗 Re-linking apps to the Python environment..."
cd "$BENCH_DIR"

# Force editable install for frappe first
./env/bin/pip install -q -e apps/frappe

# Loop through all directories in /apps and link them to the Python env.
# This fixes ModuleNotFoundError without needing a full 'bench update'.
for app_path in apps/*; do
    if [ -d "$app_path" ]; then
        app_name=$(basename "$app_path")
        if [ "$app_name" != "frappe" ]; then
            echo "   -> Linking $app_name..."
            ./env/bin/pip install -q -e "$app_path" --no-deps
        fi
    fi
done

# ------------------------------------------------------------
# 3. Environment Defaults
# ------------------------------------------------------------
export DB_HOST=${DB_HOST:-db}
export DB_PORT=${DB_PORT:-3306}
export REDIS_CACHE=${REDIS_CACHE:-redis:6379}
export REDIS_QUEUE=${REDIS_QUEUE:-$REDIS_CACHE}
export REDIS_SOCKETIO=${REDIS_SOCKETIO:-$REDIS_CACHE}
export SITE_NAME=${SITE_NAME:-devsite}
export ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
export SOCKETIO_PORT=${SOCKETIO_PORT:-9000}

# ------------------------------------------------------------
# 4. Configure common_site_config.json
# ------------------------------------------------------------
echo "🔗 Configuring common_site_config.json..."

# Sync apps.txt with the actual folders present in /apps
# This file acts as the "source of truth" for site app installations
ls -1 apps > sites/apps.txt || touch sites/apps.txt

bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g redis_cache "redis://$REDIS_CACHE"
bench set-config -g redis_queue "redis://$REDIS_QUEUE"
bench set-config -g redis_socketio "redis://$REDIS_SOCKETIO"
bench set-config -gp socketio_port "$SOCKETIO_PORT"
bench set-config -g developer_mode 1

# ------------------------------------------------------------
# 5. Wait for MariaDB Availability
# ------------------------------------------------------------
echo "⏳ Waiting for MariaDB at $DB_HOST:$DB_PORT..."
wait-for-it "$DB_HOST:$DB_PORT" -t 10

# ------------------------------------------------------------
# 6. Site Creation and App Installation
# ------------------------------------------------------------
if [ ! -d "sites/$SITE_NAME" ]; then
    echo "🏗️  Creating new site: $SITE_NAME..."

    bench new-site "$SITE_NAME" \
        --admin-password "$ADMIN_PASSWORD" \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --mariadb-user-host-login-scope='%' \
        --no-mariadb-socket \
        --set-default

    echo "📦 Installing detected apps from apps.txt..."
    while read -r app; do
        if [ -n "$app" ] && [ "$app" != "frappe" ]; then
            echo "   -> Installing $app..."
            bench --site "$SITE_NAME" install-app "$app"
        fi
    done < sites/apps.txt
else
    echo "✅ Site $SITE_NAME already exists. Syncing apps from apps.txt..."
    while read -r app; do
        if [ -n "$app" ] && [ "$app" != "frappe" ]; then
             # install-app is safe: if already in DB, it skips installation
             bench --site "$SITE_NAME" install-app "$app" || true
        fi
    done < sites/apps.txt
fi

# ------------------------------------------------------------
# 7. Finalization and Execution
# ------------------------------------------------------------
bench use "$SITE_NAME"

# Run migrate to ensure database schema matches the code
echo "🔄 Running migrate..."
bench migrate

if [ $# -gt 0 ]; then
    echo "🚀 Executing command: $@"
    exec "$@"
else
    echo "⚠️ No command provided, falling back to sleep..."
    exec sleep infinity
fi