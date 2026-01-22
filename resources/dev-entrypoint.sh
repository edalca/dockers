#!/bin/bash
set -e

echo "🚀 Starting Qota Development Environment..."

# --- 1. SINCRONIZACIÓN DE ARCHIVOS ---
if [ -z "$(ls -A /home/frappe/frappe-bench/apps)" ]; then
    echo "📂 Apps folder is empty. Syncing Frappe Framework..."
    cp -R /home/frappe/apps_backup/. /home/frappe/frappe-bench/apps/
    echo "✅ Sync complete!"
fi

echo "🔐 Adjusting permissions..."
chown -R frappe:frappe /home/frappe/frappe-bench/apps
chown -R frappe:frappe /home/frappe/frappe-bench/sites

if [[ -z "$DB_HOST" ]]; then
  echo "⚠️  DB_HOST defaulting to: db"
  export DB_HOST=db
fi

if [[ -z "$DB_PORT" ]]; then
  echo "⚠️  DB_PORT defaulting to: 3306"
  export DB_PORT=3306
fi

if [[ -z "$DB_ROOT_PASSWORD" ]]; then
  export DB_ROOT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
  echo "⚠️  DB_ROOT_PASSWORD generated automatically: $DB_ROOT_PASSWORD"
fi

if [[ -z "$REDIS_CACHE" ]]; then
  echo "⚠️  REDIS_CACHE defaulting to: redis:6379"
  export REDIS_CACHE=redis:6379
fi

if [[ -z "$SITE_NAME" ]]; then
  echo "⚠️  SITE_NAME defaulting to: devsite"
  export SITE_NAME=devsite
fi

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "⚠️  ADMIN_PASSWORD defaulting to: admin"
  export ADMIN_PASSWORD=admin
fi

export REDIS_QUEUE=${REDIS_QUEUE:-$REDIS_CACHE}
export REDIS_SOCKETIO=${REDIS_SOCKETIO:-$REDIS_CACHE}

echo "🔗 Configuring common_site_config.json..."
cd /home/frappe/frappe-bench

ls -1 apps > sites/apps.txt || touch sites/apps.txt

bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g redis_cache "redis://$REDIS_CACHE"
bench set-config -g redis_queue "redis://$REDIS_QUEUE"
bench set-config -g redis_socketio "redis://$REDIS_SOCKETIO"
bench set-config -gp socketio_port 9000

echo "⏳ Waiting for MariaDB at $DB_HOST:$DB_PORT..."
wait-for-it "$DB_HOST:$DB_PORT" -t 60

if [ ! -d "sites/$SITE_NAME" ]; then
    echo "🏗️  Creating developer site: $SITE_NAME..."
    bench new-site "$SITE_NAME" \
        --admin-password "$ADMIN_PASSWORD" \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --install-app frappe \
        --no-mariadb-socket
else
    echo "✅ Site $SITE_NAME already exists."
fi

# --- 5. ARRANQUE ---
echo "🔥 Launching Bench..."
exec bench start