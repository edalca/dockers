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

# 1) Descargar la app
RUN bench get-app qota ${QOTA_REPO}

# 2) Cambiar al directorio de la app
WORKDIR /home/frappe/frappe-bench/apps/qota

# 3) Checkout del commit
RUN git checkout ${QOTA_COMMIT}

# 4) Volver al bench
WORKDIR /home/frappe/frappe-bench

# Metadata útil
ENV FRAPPE_APP=qota
ENV FRAPPE_APP_COMMIT=${QOTA_COMMIT}
