# Version Compatibility Matrix
# ------------------------------------------------------------------------------------
# Dependency     | Frappe v16
# ------------------------------------------------------------------------------------
# Python         | 3.14 (Preview/Future)
# NodeJS         | 24.13.0  
# MariaDB Client | 11.8 (Future)
# ------------------------------------------------------------------------------------

ARG PYTHON_VERSION=3.14
ARG DEBIAN_BASE=bookworm
ARG NODE_VERSION=24.13.0
ARG NVM_VERSION=v0.40.3
ARG FRAPPE_BRANCH=version-16
ARG QOTA_REPO=https://github.com/edalca/qota.git

FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base

# Configuración de recursos de Nginx y Entrypoints
COPY resources/nginx-template.conf /templates/nginx/frappe.conf.template
COPY resources/nginx-entrypoint.sh /usr/local/bin/nginx-entrypoint.sh
COPY resources/dev-entrypoint.sh /usr/local/bin/dev-entrypoint.sh

ARG WKHTMLTOPDF_VERSION=0.12.6.1-3
ARG WKHTMLTOPDF_DISTRO=bookworm
ARG NODE_VERSION
ARG NVM_VERSION
ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}

RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    curl wget git pkg-config vim nano nginx gettext-base file \
    libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 \
    restic gpg mariadb-client less libpq-dev postgresql-client wait-for-it jq media-types \
    && mkdir -p ${NVM_DIR} \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash \
    && . ${NVM_DIR}/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm use v${NODE_VERSION} \
    && npm install -g yarn \
    && nvm alias default v${NODE_VERSION} \
    && ln -s ${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/node /usr/local/bin/node \
    && ln -s ${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/npm /usr/local/bin/npm \
    && ln -s ${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/yarn /usr/local/bin/yarn \
    && rm -rf ${NVM_DIR}/.cache \
    && if [ "$(uname -m)" = "aarch64" ]; then export ARCH=arm64; fi \
    && if [ "$(uname -m)" = "x86_64" ]; then export ARCH=amd64; fi \
    && downloaded_file=wkhtmltox_${WKHTMLTOPDF_VERSION}.${WKHTMLTOPDF_DISTRO}_${ARCH}.deb \
    && curl -sLO https://github.com/wkhtmltopdf/packaging/releases/download/$WKHTMLTOPDF_VERSION/$downloaded_file \
    && apt-get install -y ./$downloaded_file \
    && rm $downloaded_file \
    && rm -rf /var/lib/apt/lists/* \
    && rm -fr /etc/nginx/sites-enabled/default \
    && pip3 install frappe-bench --break-system-packages \
    && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /run/nginx.pid \
    && chown -R frappe:frappe /etc/nginx/conf.d /etc/nginx/nginx.conf /var/log/nginx /var/lib/nginx /run/nginx.pid \
    && chmod 755 /usr/local/bin/nginx-entrypoint.sh /usr/local/bin/dev-entrypoint.sh \
    && chmod 644 /templates/nginx/frappe.conf.template

FROM base AS builder

RUN apt-get update && apt-get install --no-install-recommends -y \
    build-essential python3-dev libmariadb-dev libssl-dev libffi-dev \
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev \
    && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe

ARG FRAPPE_BRANCH
ARG QOTA_REPO

# Inicialización del Bench e instalación automática de Qota
RUN bench init --frappe-branch=${FRAPPE_BRANCH} \
    --no-backups \
    --skip-redis-config-generation \
    --verbose \
    /home/frappe/frappe-bench && \
    cd /home/frappe/frappe-bench && \
    bench get-app qota ${QOTA_REPO} && \
    echo "{}" > sites/common_site_config.json

FROM base AS backend

USER frappe
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench
WORKDIR /home/frappe/frappe-bench

RUN cp -R /home/frappe/frappe-bench/apps /home/frappe/apps_backup

VOLUME [ \
    "/home/frappe/frappe-bench/sites", \
    "/home/frappe/frappe-bench/sites/assets", \
    "/home/frappe/frappe-bench/logs" \
    ]

CMD [ \
    "/home/frappe/frappe-bench/env/bin/gunicorn", \
    "--chdir=/home/frappe/frappe-bench/sites", \
    "--bind=0.0.0.0:8000", \
    "--threads=4", \
    "--workers=2", \
    "--worker-class=gthread", \
    "--worker-tmp-dir=/dev/shm", \
    "--timeout=120", \
    "--preload", \
    "frappe.app:application" \
    ]