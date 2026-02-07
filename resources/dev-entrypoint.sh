#!/bin/bash

set -e

echo "🚀 Starting Frappe Environment..."

APPS_DIR="/home/frappe/frappe-bench/apps"
BENCH_DIR="/home/frappe/frappe-bench"

# ------------------------------------------------------------
# 1. Descarga de apps desde FRAPPE_APPS (Base64)
# ------------------------------------------------------------
if [ -n "$FRAPPE_APPS" ]; then
    echo "🔍 Checking for apps defined in FRAPPE_APPS..."
    
    raw_json=$(echo "$FRAPPE_APPS" | base64 -d)
    count=$(echo "$raw_json" | jq '. | length')

    for (( i=0; i<$count; i++ )); do
        url=$(echo "$raw_json" | jq -r ".[$i].url")
        branch=$(echo "$raw_json" | jq -r ".[$i].branch")
        
        # Usamos basename solo para chequear si la carpeta ya existe
        # Si no existe, bench get-app se encarga de descargarla y nombrarla correctamente
        repo_name=$(basename "$url" .git)

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
# 2. Defaults de entorno
# ------------------------------------------------------------
export DB_HOST=${DB_HOST:-db}
export DB_PORT=${DB_PORT:-3306}
export REDIS_CACHE=${REDIS_CACHE:-redis:6379}
export REDIS_QUEUE=${REDIS_QUEUE:-$REDIS_CACHE}
export REDIS_SOCKETIO=${REDIS_SOCKETIO:-$REDIS_CACHE}
export SITE_NAME=${SITE_NAME:-devsite}
export ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
export SOCKETIO_PORT=${SOCKETIO_PORT:-9000}

if [[ -z "$DB_ROOT_PASSWORD" ]]; then
  export DB_ROOT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
  echo "⚠️  DB_ROOT_PASSWORD generated automatically: $DB_ROOT_PASSWORD"
fi

# ------------------------------------------------------------
# 3. Configuración de common_site_config.json
# ------------------------------------------------------------
echo "🔗 Configuring common_site_config.json..."
cd "$BENCH_DIR"

# Sincronizamos apps.txt con las carpetas reales en /apps
# Este archivo será nuestra "fuente de verdad" para instalar en el sitio
ls -1 apps > sites/apps.txt || touch sites/apps.txt

bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g redis_cache "redis://$REDIS_CACHE"
bench set-config -g redis_queue "redis://$REDIS_QUEUE"
bench set-config -g redis_socketio "redis://$REDIS_SOCKETIO"
bench set-config -gp socketio_port "$SOCKETIO_PORT"
bench set-config -g developer_mode 1

# ------------------------------------------------------------
# 4. Esperar a MariaDB
# ------------------------------------------------------------
echo "⏳ Waiting for MariaDB at $DB_HOST:$DB_PORT..."
wait-for-it "$DB_HOST:$DB_PORT" -t 10

# ------------------------------------------------------------
# 5. Crear sitio e instalar Apps (Leyendo de apps.txt)
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
             # install-app es seguro: si ya está en la DB, no hace nada
             bench --site "$SITE_NAME" install-app "$app" || true
        fi
    done < sites/apps.txt
fi

# ------------------------------------------------------------
# 6. Finalización y ejecución
# ------------------------------------------------------------
bench use "$SITE_NAME"

# Ejecutamos migrate para asegurar que la DB esté al día con el código
echo "🔄 Running migrate..."
bench migrate

if [ $# -gt 0 ]; then
    echo "🚀 Executing command: $@"
    exec "$@"
else
    echo "⚠️ No command provided, falling back to sleep..."
    exec sleep infinity
fi