# ------------------------------------------------------------
# Base dinámica de Frappe
# ------------------------------------------------------------
ARG FRAPPE_BASE_IMAGE=edalca/frappe-framework:16
FROM ${FRAPPE_BASE_IMAGE}

USER frappe
WORKDIR /home/frappe/frappe-bench

# ------------------------------------------------------------
# Configuración de Qota
# ------------------------------------------------------------
ARG QOTA_REPO=https://github.com/edalca/qota.git
ARG QOTA_COMMIT

# Instalar Qota como app (Frappe ya existe)
RUN bench get-app qota ${QOTA_REPO} \
    && cd apps/qota \
    && git checkout ${QOTA_COMMIT}

# Metadata útil
ENV FRAPPE_APP=qota
ENV FRAPPE_APP_COMMIT=${QOTA_COMMIT}
