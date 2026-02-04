#!/bin/bash

set -e

echo "🚀 Starting Frappe Environment..."

APPS_DIR="/home/frappe/frappe-bench/apps"
BENCH_DIR="/home/frappe/frappe-bench"

# ------------------------------------------------------------
# Procesar FRAPPE_APPS (Formato Lista: [ {url, branch}, ... ])
# ------------------------------------------------------------
all_app_names=""

if [ -n "$FRAPPE_APPS" ]; then
    echo "🔍 Checking for apps defined in FRAPPE_APPS..."
    
    # Decodificamos el Base64 una sola vez
    raw_json=$(echo "$FRAPPE_APPS" | base64 -d)
    
    # Obtenemos la cantidad de apps en el array usando jq
    count=$(echo "$raw_json" | jq '. | length')

    for (( i=0; i<$count; i++ )); do
        url=$(echo "$raw_json" | jq -r ".[$i].url")
        branch=$(echo "$raw_json" | jq -r ".[$i].branch")
        
        # Extraer el nombre de la app desde la URL
        # Ejemplo: https://github.com/frappe/erpnext.git -> erpnext
        app_name=$(basename "$url" .git)
        all_app_names="$all_app_names $app_name"

        if [ ! -d "$APPS_DIR/$app_name" ]; then
            echo "⬇️  App '$app_name' not found. Installing from $url..."
            bench get-app --branch "$branch" "$url"
        else
            echo "✅ App '$app_name' is already present in $APPS_DIR."
        fi
    done
else
    echo "ℹ️  No FRAPPE_APPS defined. Using base Frappe only."
fi

# ------------------------------------------------------------
# Defaults de entorno
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
# Configuración de common_site_config.json
# ------------------------------------------------------------
echo "🔗 Configuring common_site_config.json..."
cd "$BENCH_DIR"

# Sincronizar el archivo apps.txt con las carpetas físicas
ls -1 apps > sites/apps.txt || touch sites/apps.txt

bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g redis_cache "redis://$REDIS_CACHE"
bench set-config -g redis_queue "redis://$REDIS_QUEUE"
bench set-config -g redis_socketio "redis://$REDIS_SOCKETIO"
bench set-config -gp socketio_port "$SOCKETIO_PORT"

# ------------------------------------------------------------
# Esperar a que MariaDB esté lista
# ------------------------------------------------------------
echo "⏳ Waiting for MariaDB at $DB_HOST:$DB_PORT..."
wait-for-it "$DB_HOST:$DB_PORT" -t 60

# ------------------------------------------------------------
# Crear sitio e instalar Apps en la Base de Datos
# ------------------------------------------------------------
if [ ! -d "sites/$SITE_NAME" ]; then
    echo "🏗️  Creating new site: $SITE_NAME..."

    bench new-site "$SITE_NAME" \
        --admin-password "$ADMIN_PASSWORD" \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --install-app frappe \
        --no-mariadb-socket

    # Instalar las apps descargadas en el sitio nuevo
    for app in $all_app_names; do
        if [ "$app" != "frappe" ]; then
            echo "📦 Installing $app on site $SITE_NAME..."
            bench --site "$SITE_NAME" install-app "$app"
        fi
    done
else
    echo "✅ Site $SITE_NAME already exists. Syncing apps..."
    # Intentar instalar apps que falten por si el JSON cambió
    for app in $all_app_names; do
        if [ "$app" != "frappe" ]; then
             # El comando install-app es seguro; si ya está instalada, no hace nada
             bench --site "$SITE_NAME" install-app "$app" || true
        fi
    done
fi

bench use "$SITE_NAME"

# ------------------------------------------------------------
# Ejecución del comando final
# ------------------------------------------------------------
# $@ recibe los argumentos del CMD del Dockerfile (Gunicorn)
if [ $# -gt 0 ]; then
    echo "🚀 Executing command: $@"
    exec "$@"
else
    echo "⚠️ No command provided, staying alive with sleep..."
    exec sleep infinity
fi