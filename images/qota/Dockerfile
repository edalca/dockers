# ------------------------------------------------------------
# Base dinámica de Frappe (Tu imagen optimizada)
# ------------------------------------------------------------
ARG FRAPPE_BASE_IMAGE=edalca/frappe-framework:16
FROM ${FRAPPE_BASE_IMAGE}

# Redeclarar ARGs para que estén disponibles en esta etapa
ARG QOTA_REPO=https://github.com/edalca/qota.git
ARG QOTA_COMMIT
ARG QOTA_VERSION=16
ARG FRAPPE_VERSION=16

# ------------------------------------------------------------
# Metadatos de la Aplicación
# ------------------------------------------------------------
LABEL org.opencontainers.image.title="Qota App" \
    org.opencontainers.image.description="Robust Frappe-based management system for water boards and community associations, ensuring transparent accounting and automated billing." \
    org.opencontainers.image.vendor="edalca" \
    org.opencontainers.image.version="${QOTA_VERSION}" \
    org.opencontainers.image.authors="Edwin Alonso <edwinalonso162@hotmail.com>"

USER root
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe/frappe-bench

ENV BASH_ENV=/home/frappe/.bashrc
# ------------------------------------------------------------
# Instalación de Qota
# ------------------------------------------------------------

# 1) Descargar la app y limpiar caché de una vez para ahorrar espacio
RUN bench get-app --skip-assets qota ${QOTA_REPO} \
    && rm -rf ~/.cache/pip ~/.cache/yarn

# 2) Manejo del Commit y dependencias
# Cambiamos a la app, hacemos checkout y regresamos al bench en una sola capa
RUN cd apps/qota \
    && git checkout ${QOTA_COMMIT} \
    && cd ../.. \
    && bench setup requirements



