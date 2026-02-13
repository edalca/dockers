# ------------------------------------------------------------
# Dynamic Frappe Base
# ------------------------------------------------------------
ARG FRAPPE_BASE_IMAGE=edalca/frappe:16
FROM ${FRAPPE_BASE_IMAGE}

ARG ERPNEXT_REPO=https://github.com/frappe/erpnext.git
ARG ERPNEXT_BRANCH=version-16

ARG HRMS_REPO=https://github.com/frappe/hrms.git
ARG HRMS_BRANCH=version-16
ARG HRMS_VERSION=16

# ------------------------------------------------------------
# Application Metadata
# ------------------------------------------------------------
LABEL org.opencontainers.image.title="HRMS App" \
    org.opencontainers.image.description="Robust Frappe-based Human Resource Management System." \
    org.opencontainers.image.vendor="edalca" \
    org.opencontainers.image.version="${HRMS_VERSION}" \
    org.opencontainers.image.authors="Edwin Alonso <edwinalonso162@hotmail.com>"

USER root
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe/frappe-bench

ENV BASH_ENV=/home/frappe/.bashrc
RUN echo '{"socketio_port": 9000}' > sites/common_site_config.json
# ------------------------------------------------------------
# HRMS Installation
# ------------------------------------------------------------
RUN bench get-app ${ERPNEXT_REPO} --branch ${ERPNEXT_BRANCH}

RUN bench get-app ${HRMS_REPO} --branch ${HRMS_BRANCH}