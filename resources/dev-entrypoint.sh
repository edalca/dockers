#!/bin/bash
set -e

echo "🚀 Starting Qota Development Environment..."

if [[ -z "$DB_HOST" ]]; then
  echo "DB_HOST defaulting to db"
  export DB_HOST=db
fi

if [[ -z "$DB_PORT" ]]; then
  echo "DB_PORT defaulting to 3306"
  export DB_PORT=3306
fi

if [[ -z "$DB_ROOT_PASSWORD" ]]; then
  echo "DB_ROOT_PASSWORD defaulting to qota_dev_root"
  export DB_ROOT_PASSWORD=qota_dev_root
fi

if [[ -z "$REDIS_CACHE" ]]; then
  echo "REDIS_CACHE defaulting to redis:6379"
  export REDIS_CACHE=redis:6379
fi

if [[ -z "$REDIS_QUEUE" ]]; then
  export REDIS_QUEUE=$REDIS_CACHE
fi

if [[ -z "$REDIS_SOCKETIO" ]]; then
  export REDIS_SOCKETIO=$REDIS_CACHE
fi

if [[ -z "$SITE_NAME" ]]; then
  echo "SITE_NAME defaulting to qota.test"
  export SITE_NAME=qota.test
fi

if [[ -z "$ADMIN_PASSWORD" ]]; then
  export ADMIN_PASSWORD=admin
fi


echo "🔗 Configuring common_site_config.json..."
ls -1 apps > sites/apps.txt || touch sites/apps.txt
bench set-config -g db_host $DB_HOST
bench set-config -gp db_port $DB_PORT
bench set-config -g redis_cache "redis://$REDIS_CACHE"
bench set-config -g redis_queue "redis://$REDIS_QUEUE"
bench set-config -g redis_socketio "redis://$REDIS_SOCKETIO"
bench set-config -gp socketio_port 9000


echo "⏳ Waiting for MariaDB at $DB_HOST..."
wait-for-it $DB_HOST:$DB_PORT -t 60

if [ ! -d "sites/$SITE_NAME" ]; then
    echo "🏗️ Creating site $SITE_NAME..."
    bench new-site $SITE_NAME --admin-password $ADMIN_PASSWORD --mariadb-root-password $DB_ROOT_PASSWORD --install-app frappe --no-mariadb-socket
fi

echo "🔥 Launching Bench..."
bench start