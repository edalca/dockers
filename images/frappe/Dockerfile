# ==============================================================================
# FRAPPE VERSION CONFIGURATION GUIDE
# Toggle the ARG values below based on the version you want to build.
# ==============================================================================
#
# --- CONFIGURATION FOR FRAPPE v16 (Edge/Dev) ---
# ARG PYTHON_VERSION=3.14.3
# ARG NODE_VERSION=24.13.0
# ARG NVM_VERSION=v0.40.4
# ARG FRAPPE_BRANCH=version-16
#
# --- CONFIGURATION FOR FRAPPE v15 (Stable/LTS) ---
# ARG PYTHON_VERSION=3.11.9      (Python 3.14 is too new for v15, use 3.11 or 3.12)
# ARG NODE_VERSION=20.18.0       (v15 requires Node 18 or 20 LTS)
# ARG NVM_VERSION=v0.39.7
# ARG FRAPPE_BRANCH=version-15
#
# ==============================================================================

# ------------------------------------------------------------------------------------
# Frappe Framework - Full Production Runtime
# ------------------------------------------------------------------------------------

# --- CURRENT CONFIGURATION (Defaulting to v16) ---
ARG PYTHON_VERSION=3.14.3
ARG DEBIAN_BASE=bookworm
ARG NODE_VERSION=24.13.0
ARG NVM_VERSION=v0.40.4
ARG FRAPPE_BRANCH=version-16
ARG FRAPPE_PATH=https://github.com/edalca/frappe

FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base

ARG NODE_VERSION
ARG NVM_VERSION

ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}

ARG WKHTMLTOPDF_VERSION=0.12.6.1-3
ARG WKHTMLTOPDF_DISTRO=bookworm

RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    curl wget git pkg-config vim nano nginx gettext-base file \
    libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 \
    restic gpg mariadb-client less libpq-dev postgresql-client \
    wait-for-it jq media-types \
    # Added build dependencies here for the final image (Fixes pip install errors in dev)
    build-essential python3-dev libmariadb-dev default-libmysqlclient-dev \
    libjpeg-dev zlib1g-dev \
    && mkdir -p ${NVM_DIR} \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash \
    && . ${NVM_DIR}/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm use v${NODE_VERSION} \
    && npm install -g yarn \
    && nvm alias default v${NODE_VERSION} \
    && NODE_BIN=$(ls -d ${NVM_DIR}/versions/node/v${NODE_VERSION}* | head -n 1)/bin \
    && ln -s ${NODE_BIN}/node /usr/local/bin/node \
    && ln -s ${NODE_BIN}/npm /usr/local/bin/npm \
    && ln -s ${NODE_BIN}/yarn /usr/local/bin/yarn \
    && rm -rf ${NVM_DIR}/.cache \
    # Architecture detection for wkhtmltopdf
    && if [ "$(uname -m)" = "aarch64" ]; then export ARCH=arm64; fi \
    && if [ "$(uname -m)" = "x86_64" ]; then export ARCH=amd64; fi \
    && downloaded_file=wkhtmltox_${WKHTMLTOPDF_VERSION}.${WKHTMLTOPDF_DISTRO}_${ARCH}.deb \
    && curl -sLO https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}/${downloaded_file} \
    && apt-get install -y ./${downloaded_file} \
    && rm ${downloaded_file} \
    && rm -rf /var/lib/apt/lists/* \
    # Cleanup Nginx and prep for non-root execution
    && rm -fr /etc/nginx/sites-enabled/default \
    && pip3 install frappe-bench \
    && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /run/nginx.pid \
    && chown -R frappe:frappe /etc/nginx /var/log/nginx /var/lib/nginx /run/nginx.pid

FROM base AS builder
ARG FRAPPE_BRANCH
ARG FRAPPE_PATH


RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    redis-tools rlwrap tk8.6-dev \
    libcairo2-dev libpango1.0-dev libgif-dev librsvg2-dev \
    libffi-dev liblcms2-dev libldap2-dev \
    libsasl2-dev libtiff5-dev libwebp-dev libbz2-dev \
    && rm -rf /var/lib/apt/lists/*

USER frappe

ARG FRAPPE_BRANCH
ARG FRAPPE_PATH
ARG FRAPPE_VERSION=16.0.0

RUN bench init \
    --frappe-branch=${FRAPPE_BRANCH} \
    --frappe-path=${FRAPPE_PATH} \
    --no-backups \
    --skip-redis-config-generation \
    --verbose \
    /home/frappe/frappe-bench \
    && echo "{}" > /home/frappe/frappe-bench/sites/common_site_config.json

FROM base AS backend

ARG FRAPPE_VERSION

LABEL org.opencontainers.image.title="Frappe Framework Runtime" \
    org.opencontainers.image.description="Secure Frappe runtime optimized for multi-stage builds and non-root execution." \
    org.opencontainers.image.vendor="edalca" \
    org.opencontainers.image.version="${FRAPPE_VERSION}" \
    org.opencontainers.image.authors="Edwin Alonso <edwinalonso162@hotmail.com>"

COPY resources/nginx-template.conf /templates/nginx/frappe.conf.template
COPY resources/nginx-entrypoint.sh /usr/local/bin/nginx-entrypoint.sh
COPY resources/dev-entrypoint.sh /usr/local/bin/dev-entrypoint.sh

RUN chmod 755 /usr/local/bin/nginx-entrypoint.sh \
    && chmod 755 /usr/local/bin/dev-entrypoint.sh \
    && chmod 644 /templates/nginx/frappe.conf.template

USER frappe
WORKDIR /home/frappe/frappe-bench
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

VOLUME ["/home/frappe/frappe-bench/sites", "/home/frappe/frappe-bench/sites/assets", "/home/frappe/frappe-bench/logs"]

CMD ["/home/frappe/frappe-bench/env/bin/gunicorn", \
    "--chdir=/home/frappe/frappe-bench/sites", \
    "--bind=0.0.0.0:8000", \
    "frappe.app:application"]