#!/bin/bash

# --- 1. Let's Encrypt Preparation (Always runs just in case) ---
ACME_FILE="/letsencrypt/acme.json"
mkdir -p /letsencrypt
if [ ! -f "$ACME_FILE" ]; then
  touch "$ACME_FILE"
fi
chmod 600 "$ACME_FILE"

# --- 2. Logic for CERT_TYPE ---
if [ "$CERT_TYPE" == "custom" ]; then
  echo "CERT_TYPE is 'custom'. Creating manual certificate files..."
  
  # Directory for internal storage
  mkdir -p /certs
  
  # Create the .crt and .key from Env Vars
  # Using echo -e to handle the \n characters
  echo -e "$CUSTOM_CERT_CONTENT" > /certs/certificate.crt
  echo -e "$CUSTOM_KEY_CONTENT" > /certs/private.key
  
  # Create the dynamic config file expected by your Docker command
  cat <<EOF > /etc/traefik/cert.yaml
tls:
  certificates:
    - certFile: /certs/certificate.crt
      keyFile: /certs/private.key
EOF
  echo "File /etc/traefik/cert.yaml created successfully."

elif [ "$CERT_TYPE" == "lets" ]; then
  echo "CERT_TYPE is 'lets'. Traefik will use Let's Encrypt resolver."
  # We create an empty cert.yaml so Traefik doesn't complain it's missing
  touch /etc/traefik/cert.yaml
else
  echo "No specific CERT_TYPE detected. Starting Traefik with default config."
  touch /etc/traefik/cert.yaml
fi

echo "Initialization complete. Launching Traefik..."

# --- 3. Run Traefik ---
exec traefik "$@"