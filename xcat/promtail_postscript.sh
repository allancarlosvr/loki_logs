#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# xCAT postscript - Promtail deployment for HPC compute nodes
# Compatible baseline:
# - RHEL 8.6
# - glibc 2.28
# Notes:
# - Uses Promtail 3.5.6 via ZIP (validated in cluster)
# - Runs as root to read /var/log/messages
# - Sends logs to Loki on master node
# -----------------------------------------------------------------------------

PROMTAIL_VERSION="3.5.6"
PROMTAIL_BIN="/usr/bin/promtail"
PROMTAIL_ZIP_URL="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"

PROMTAIL_CONFIG_DIR="/etc/promtail"
PROMTAIL_CONFIG_FILE="${PROMTAIL_CONFIG_DIR}/config.yml"
PROMTAIL_POSITIONS_DIR="/var/lib/promtail"
PROMTAIL_POSITIONS_FILE="${PROMTAIL_POSITIONS_DIR}/positions.yaml"

SYSTEMD_UNIT_FILE="/etc/systemd/system/promtail.service"

LOKI_HOST="dc1clu0005-mstr"
LOKI_PORT="3100"

JOB_NAME="syslog"
SCRAPE_LOG_PATH="/var/log/messages"

echo "==> Starting xCAT Promtail postscript..."

# -----------------------------------------------------------------------------
# 1. Root check
# -----------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Install unzip if needed
# -----------------------------------------------------------------------------
echo "==> Installing unzip if needed..."
dnf install -y unzip

# -----------------------------------------------------------------------------
# 3. Install Promtail binary if not already present
# -----------------------------------------------------------------------------
if [[ ! -x "${PROMTAIL_BIN}" ]]; then
  echo "==> Promtail binary not found. Downloading version ${PROMTAIL_VERSION}..."

  curl -fL -o /tmp/promtail.zip "${PROMTAIL_ZIP_URL}"

  cd /tmp
  unzip -o promtail.zip

  install -m 0755 /tmp/promtail-linux-amd64 "${PROMTAIL_BIN}"

  echo "==> Promtail installed:"
  "${PROMTAIL_BIN}" --version
else
  echo "==> Promtail binary already present at ${PROMTAIL_BIN}"
  "${PROMTAIL_BIN}" --version || true
fi

# -----------------------------------------------------------------------------
# 4. Create required directories
# -----------------------------------------------------------------------------
echo "==> Creating Promtail directories..."
mkdir -p "${PROMTAIL_CONFIG_DIR}"
mkdir -p "${PROMTAIL_POSITIONS_DIR}"

chmod 755 "${PROMTAIL_CONFIG_DIR}"
chmod 755 "${PROMTAIL_POSITIONS_DIR}"

# -----------------------------------------------------------------------------
# 5. Write Promtail configuration
# -----------------------------------------------------------------------------
echo "==> Writing Promtail configuration to ${PROMTAIL_CONFIG_FILE}..."

cat > "${PROMTAIL_CONFIG_FILE}" <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: ${PROMTAIL_POSITIONS_FILE}

clients:
  - url: http://${LOKI_HOST}:${LOKI_PORT}/loki/api/v1/push

scrape_configs:
  - job_name: ${JOB_NAME}
    static_configs:
      - targets:
          - localhost
        labels:
          job: ${JOB_NAME}
          host: $(hostname -s)
          __path__: ${SCRAPE_LOG_PATH}
EOF

chmod 644 "${PROMTAIL_CONFIG_FILE}"

# -----------------------------------------------------------------------------
# 6. Create systemd service
# -----------------------------------------------------------------------------
echo "==> Creating systemd unit ${SYSTEMD_UNIT_FILE}..."

cat > "${SYSTEMD_UNIT_FILE}" <<'EOF'
[Unit]
Description=Promtail service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/promtail -config.file /etc/promtail/config.yml
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${SYSTEMD_UNIT_FILE}"

# -----------------------------------------------------------------------------
# 7. Reload systemd and start service
# -----------------------------------------------------------------------------
echo "==> Reloading systemd..."
systemctl daemon-reload

echo "==> Enabling Promtail..."
systemctl enable promtail

echo "==> Restarting Promtail..."
systemctl restart promtail

# -----------------------------------------------------------------------------
# 8. Validate service
# -----------------------------------------------------------------------------
echo "==> Promtail service status:"
systemctl status promtail --no-pager || true

echo "==> Testing connectivity to Loki..."
if curl -fsS "http://${LOKI_HOST}:${LOKI_PORT}/ready" >/dev/null 2>&1; then
  echo "SUCCESS: Loki is reachable at ${LOKI_HOST}:${LOKI_PORT}"
else
  echo "WARNING: Loki is not reachable at ${LOKI_HOST}:${LOKI_PORT}"
  echo "Check DNS/network/firewall."
fi

echo "==> xCAT Promtail postscript finished."
