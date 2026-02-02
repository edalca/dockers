#!/bin/bash

echo "🚀 Starting Qota Development Environment..."

APPS_DIR="/home/frappe/frappe-bench/apps"
BENCH_DIR="/home/frappe/frappe-bench"

apps=""

# ------------------------------------------------------------
# Leer apps desde FRAPPE_APPS (Base64)
# ------------------------------------------------------------
if [ -n "$FRAPPE_APPS" ]; then
    apps=$(echo "$FRAPPE_APPS" | base64 -d | jq -r 'keys[]')
fi

# ------------------------------------------------------------
# Bootstrap de apps si el directorio está vacío
# ------------------------------------------------------------
if [ -z "$(ls -A "$APPS_DIR" 2>/dev/null)" ]; then
    echo "📂 Apps folder is empty. Bootstrapping from FRAPPE_APPS..."

    # 1️⃣ Instalar frappe primero
    echo "⬇️ Installing frappe..."
    bench get-app --branch "$FRAPPE_BRANCH" "$FRAPPE_PATH"

    # 2️⃣ Instalar el resto de apps
    for app in $apps; do
        if [ "$app" != "frappe" ]; then
            url=$(echo "$FRAPPE_APPS" | base64 -d | jq -r --arg app "$app" '.[$app].url')
            branch=$(echo "$FRAPPE_APPS" | base64 -d | jq -r --arg app "$app" '.[$app].branch')

            echo "⬇️ Installing $app..."
            bench get-app --branch "$branch" "$url"
        fi
    done

    echo "✅ All apps installed."
else
    echo "✅ Apps folder is not empty. Skipping app installation."
fi

# ------------------------------------------------------------
# Defaults de entorno (solo desarrollo)
# ------------------------------------------------------------
export DB_HOST=${DB_HOST:-db}
export DB_PORT=${DB_PORT:-3306}
export REDIS_CACHE=${REDIS_CACHE:-redis:6379}
export REDIS_QUEUE=${REDIS_QUEUE:-$REDIS_CACHE}
export REDIS_SOCKETIO=${REDIS_SOCKETIO:-$REDIS_CACHE}
export SITE_NAME=${SITE_NAME:-devsite}
export ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}

if [[ -z "$DB_ROOT_PASSWORD" ]]; then
  export DB_ROOT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
  echo "⚠️  DB_ROOT_PASSWORD generated automatically: $DB_ROOT_PASSWORD"
fi

# ------------------------------------------------------------
# Configuración global
# ------------------------------------------------------------
echo "🔗 Configuring common_site_config.json..."
cd "$BENCH_DIR"

ls -1 apps > sites/apps.txt || touch sites/apps.txt

bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g redis_cache "redis://$REDIS_CACHE"
bench set-config -g redis_queue "redis://$REDIS_QUEUE"
bench set-config -g redis_socketio "redis://$REDIS_SOCKETIO"
bench set-config -gp socketio_port 9000

# ------------------------------------------------------------
# Esperar base de datos
# ------------------------------------------------------------
echo "⏳ Waiting for MariaDB at $DB_HOST:$DB_PORT..."
wait-for-it "$DB_HOST:$DB_PORT" -t 60

# ------------------------------------------------------------
# Crear sitio si no existe
# ------------------------------------------------------------
if [ ! -d "sites/$SITE_NAME" ]; then
    echo "🏗️  Creating developer site: $SITE_NAME..."

    bench new-site "$SITE_NAME" \
        --admin-password "$ADMIN_PASSWORD" \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --install-app frappe \
        --no-mariadb-socket

    # Instalar apps adicionales en el sitio
    for app in $apps; do
        if [ "$app" != "frappe" ]; then
            echo "📦 Installing $app on site $SITE_NAME..."
            bench --site "$SITE_NAME" install-app "$app"
        fi
    done
else
    echo "✅ Site $SITE_NAME already exists. Assuming apps are installed."
fi

# ------------------------------------------------------------