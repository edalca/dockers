# Version Compatibility Matrix
# ------------------------------------------------------------------------------------
# Dependency     | Frappe v14/v15 (Default) | Frappe v16/develop
# ------------------------------------------------------------------------------------
# Python         | 3.10+ (use 3.11.6)       | 3.14 (Preview/Future)
# NodeJS         | 18+   (use 20.x)         | 24   (Future)
# MariaDB Client | 10.6+                    | 11.8 (Future)
# ------------------------------------------------------------------------------------
# Usage:
# For v15: docker build .
# For v16: docker build --build-arg FRAAPE_BRANCH=develop --build-arg PYTHON_VERSION=3.14 --build-arg NODE_VERSION=24 .
ARG PYTHON_VERSION=3.11.6
ARG DEBIAN_BASE=bookworm
ARG NODE_VERSION=20.19.2
ARG NVM_VERSION=v0.40.3
ARG FRAPPE_BRANCH=version-15
ARG FRAPPE_PATH=https://github.com/frappe/frappe

FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base

COPY resources/nginx-template.conf /templates/nginx/frappe.conf.template
COPY resources/nginx-entrypoint.sh /usr/local/bin/nginx-entrypoint.sh
COPY resources/dev-entrypoint.sh /usr/local/bin/dev-entrypoint.sh

ARG WKHTMLTOPDF_VERSION=0.12.6.1-3
ARG WKHTMLTOPDF_DISTRO=bookworm
ARG NODE_VERSION
ARG NVM_VERSION
ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}
ENV FRAPPE_BRANCH=${FRAPPE_BRANCH}
ENV FRAPPE_PATH=${FRAPPE_PATH}

RUN useradd -ms /bin/bash frappe \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
  curl \
  wget \
  git \
  pkg-config \
  vim \
  nano \
  nginx \
  gettext-base \
  file \
  libpango-1.0-0 \
  libharfbuzz0b \
  libpangoft2-1.0-0 \
  libpangocairo-1.0-0 \
  restic \
  gpg \
  mariadb-client \
  less \
  libpq-dev \
  postgresql-client \
  wait-for-it \
  jq \
  media-types \
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
  && echo 'export NVM_DIR="/home/frappe/.nvm"' >>/home/frappe/.bashrc \
  && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >>/home/frappe/.bashrc \
  && echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >>/home/frappe/.bashrc \
  && if [ "$(uname -m)" = "aarch64" ]; then export ARCH=arm64; fi \
  && if [ "$(uname -m)" = "x86_64" ]; then export ARCH=amd64; fi \
  && downloaded_file=wkhtmltox_${WKHTMLTOPDF_VERSION}.${WKHTMLTOPDF_DISTRO}_${ARCH}.deb \
  && curl -sLO https://github.com/wkhtmltopdf/packaging/releases/download/$WKHTMLTOPDF_VERSION/$downloaded_file \
  && apt-get install -y ./$downloaded_file \
  && rm $downloaded_file \
  && rm -rf /var/lib/apt/lists/* \
  && rm -fr /etc/nginx/sites-enabled/default \
  && pip3 install frappe-bench \
  && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
  && ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log \
  && touch /run/nginx.pid \
  && chown -R frappe:frappe /etc/nginx/conf.d \
  && chown -R frappe:frappe /etc/nginx/nginx.conf \
  && chown -R frappe:frappe /var/log/nginx \
  && chown -R frappe:frappe /var/lib/nginx \
  && chown -R frappe:frappe /run/nginx.pid \
  && chmod 755 /usr/local/bin/nginx-entrypoint.sh \
  && chmod 644 /templates/nginx/frappe.conf.template \
  && chmod 755 /usr/local/bin/dev-entrypoint.sh

FROM base AS builder

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
  libcairo2-dev \
  libpango1.0-dev \
  libjpeg-dev \
  libgif-dev \
  librsvg2-dev \
  libpq-dev \
  libffi-dev \
  liblcms2-dev \
  libldap2-dev \
  libmariadb-dev \
  libsasl2-dev \
  libtiff5-dev \
  libwebp-dev \
  redis-tools \
  rlwrap \
  tk8.6-dev \
  cron \
  gcc \
  build-essential \
  libbz2-dev \
  && rm -rf /var/lib/apt/lists/*

ARG APPS_JSON_BASE64
RUN if [ -n "${APPS_JSON_BASE64}" ]; then \
  echo "${APPS_JSON_BASE64}" | base64 -d > /home/frappe/apps.json; \
  fi

USER frappe

RUN export APP_INSTALL_ARGS="" && \
  if [ -n "${APPS_JSON_BASE64}" ]; then \
  export APP_INSTALL_ARGS="--apps_path=/home/frappe/apps.json"; \
  fi && \
  bench init ${APP_INSTALL_ARGS}\
  --frappe-branch=${FRAPPE_BRANCH} \
  --frappe-path=${FRAPPE_PATH} \
  --no-backups \
  --skip-redis-config-generation \
  --verbose \
  /home/frappe/frappe-bench && \
  cd /home/frappe/frappe-bench && \
  echo "{}" > sites/common_site_config.json 

FROM base AS backend

USER frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

ENV FRAPPE_APPS=${APPS_JSON_BASE64}

WORKDIR /home/frappe/frappe-bench

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