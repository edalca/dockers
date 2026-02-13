# ------------------------------------------------------------
# Frappe Dynamic Base (Optimized Image)
# ------------------------------------------------------------
ARG FRAPPE_BASE_IMAGE=edalca/frappe:16
FROM ${FRAPPE_BASE_IMAGE}

# Redeclare ARGs for this stage
ARG QOTA_PATH=https://github.com/edalca/qota.git
ARG QOTA_BRANCH=version-16
ARG QOTA_VERSION=16

# ------------------------------------------------------------
# Application Metadata
# ------------------------------------------------------------
LABEL org.opencontainers.image.title="Qota App" \
    org.opencontainers.image.description="Robust Frappe-based management system..." \
    org.opencontainers.image.vendor="edalca" \
    org.opencontainers.image.version="${QOTA_VERSION}" \
    org.opencontainers.image.authors="Edwin Alonso <edwinalonso162@hotmail.com>"

USER root
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe/frappe-bench

ENV BASH_ENV=/home/frappe/.bashrc

# ------------------------------------------------------------
# Qota Installation & Asset Compilation
# ------------------------------------------------------------

RUN bench get-app qota ${QOTA_PATH} --branch ${QOTA_BRANCH} \
    && rm -rf ~/.cache/pip ~/.cache/yarn

# This generates the JS/CSS files inside the image layer
RUN bench build --app qota





