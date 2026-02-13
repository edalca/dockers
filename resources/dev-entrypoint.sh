#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "🚀 Starting Frappe Environment"

APPS_DIR="/home/frappe/frappe-bench/apps"
BENCH_DIR="/home/frappe/frappe-bench"

# ------------------------------------------------------------
# 1. Download apps defined in FRAPPE_APPS (Base64 JSON)
# ------------------------------------------------------------
if [ -n "$FRAPPE_APPS" ]; then
    echo "🔍 Checking for apps defined in FRAPPE_APPS..."
    raw_json=$(echo "$FRAPPE_APPS" | base64 -d)
    count=$(echo "$raw_json" | jq '. | length')

    for (( i=0; i<$count; i++ )); do
        url=$(echo "$raw_json" | jq -r ".[$i].url")
        branch=$(echo "$raw_json" | jq -r ".[$i].branch")
        repo_name=$(basename "$url" .git)

        if [ ! -d "$APPS_DIR/$repo_name" ]; then
            echo "⬇️  Installing $repo_name from $url..."
            bench get-app --branch "$branch" "$url"
        else
            echo "✅ App '$repo_name' is already present."
        fi
    done
fi

# ------------------------------------------------------------
# 2. Re-link apps to Python environment (Persistent Fix)
# ------------------------------------------------------------
echo "🔗 Re-linking apps to the Python environment..."
cd "$BENCH_DIR"

# Force editable install for frappe
./env/bin/pip install -q -e apps/frappe

for app_path in apps/*; do
    if [ -d "$app_path" ]; then
        app_name=$(basename "$app_path")
        if [ "$app_name" != "frappe" ]; then
            echo "   -> Linking $app_name..."
            ./env/bin/pip install -q -e "$app_path" --no-deps
            
            if [ -f "$app_path/requirements.txt" ]; then
                echo "   -> Installing requirements for $app_name..."
                ./env/bin/pip install -q -r "$app_path/requirements.txt"
            fi
        fi
    fi
done

# ------------------------------------------------------------
# 3. Smart Configuration of common_site_config.json
# ------------------------------------------------------------
echo "⚙️  Configuring common_site_config.json..."

# Only update apps.txt if directories have actually changed
# This prevents invalidating existing compiled assets
ls -1 apps > sites/apps.temp
if ! cmp -s sites/apps.temp sites/apps.txt; then
    echo "📝 Updating apps.txt due to changes in the apps directory..."
    mv sites/apps.temp sites/apps.txt
else
    rm sites/apps.temp
    echo "✅ apps.txt is up to date."
fi

bench set-config -g db_host "${DB_HOST:-db}"
bench set-config -gp db_port "${DB_PORT:-3306}"
bench set-config -g redis_cache "redis://${REDIS_CACHE:-redis:6379/0}"
bench set-config -g redis_queue "redis://${REDIS_QUEUE:-redis:6379/1}"
bench set-config -g redis_socketio "redis://${REDIS_SOCKETIO:-redis:6379/2}"
bench set-config -gp socketio_port "${SOCKETIO_PORT:-9000}"
bench set-config -g developer_mode 1

# ------------------------------------------------------------
# 4. Asset Refresh (Skip bench build if symlinks are okay)
# ------------------------------------------------------------
echo "📦 Refreshing asset symlinks..."
# Re-links site assets to app public folders without full compilation
bench setup symlinks

# ------------------------------------------------------------
# 5. Database Wait and Migration
# ------------------------------------------------------------
echo "⏳ Waiting for MariaDB availability..."
wait-for-it "${DB_HOST:-db}:${DB_PORT:-3306}" -t 15

if [ ! -d "sites/$SITE_NAME" ]; then
    echo "🏗️  Creating new site: $SITE_NAME..."
    bench new-site "$SITE_NAME" \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --set-default
else
    echo "✅ Site $SITE_NAME detected."
    bench use "$SITE_NAME"
fi

echo "🔄 Running database migration..."
bench migrate

# ------------------------------------------------------------
# 6. Execution
# ------------------------------------------------------------
if [ $# -gt 0 ]; then
    echo "🚀 Executing command: $@"
    exec "$@"
else
    echo "⚠️  No command provided, falling back to sleep..."
    exec sleep infinity
fi