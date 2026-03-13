#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Promtail installation script for HPC compute nodes
# Target nodes: n01, n02, n03, n04, n05
# Loki server: dc1clu0005-mstr:3100
# OS: RHEL / Rocky / Alma
# -----------------------------------------------------------------------------

LOKI_HOST="${LOKI_HOST:-dc1clu0005-mstr}"
LOKI_PORT="${LOKI_PORT:-3100}"
PROMTAIL_CONFIG_DIR="/etc/promtail"
PROMTAIL_CONFIG_FILE="${PROMTAIL_CONFIG_DIR}/config.yml"
PROMTAIL_POSITIONS_DIR="/var/lib/promtail"
PROMTAIL_POSITIONS_FILE="${PROMTAIL_POSITIONS_DIR}/positions.yaml"

# Default log path for initial validation
SCRAPE_LOG_PATH="${SCRAPE_LOG_PATH:-/var/log/messages}"
JOB_NAME="${JOB_NAME:-syslog}"

echo "==> Starting Promtail installation..."

# -----------------------------------------------------------------------------
# 1. Check privileges
# -----------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Check required commands
# -----------------------------------------------------------------------------
for cmd in curl grep cut dnf systemctl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${cmd}"
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# 3. Define Promtail version compatible with RHEL 8.6 / glibc 2.28
# -----------------------------------------------------------------------------
PROMTAIL_VERSION="${PROMTAIL_VERSION:-3.5.6}"

echo "==> Using Promtail version: ${PROMTAIL_VERSION}"

PROMTAIL_ZIP_URL="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"

echo "==> Promtail ZIP URL: ${PROMTAIL_ZIP_URL}"

# -----------------------------------------------------------------------------
# 4. Download and install Promtail from ZIP
# -----------------------------------------------------------------------------
TMP_ZIP="/tmp/promtail.zip"

echo "==> Installing unzip package if needed..."
dnf install -y unzip

echo "==> Downloading Promtail ZIP..."
curl -fL -o "${TMP_ZIP}" "${PROMTAIL_ZIP_URL}"

echo "==> Extracting Promtail..."
cd /tmp
unzip -o "${TMP_ZIP}"

echo "==> Installing Promtail binary..."
install -m 0755 /tmp/promtail-linux-amd64 /usr/bin/promtail

echo "==> Checking Promtail version..."
/usr/bin/promtail --version

# -----------------------------------------------------------------------------
# 5. Create promtail user if needed
# -----------------------------------------------------------------------------
echo "==> Ensuring promtail user exists..."
if ! id promtail >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /sbin/nologin promtail
fi

# -----------------------------------------------------------------------------
# 6. Prepare Promtail directories
# -----------------------------------------------------------------------------
echo "==> Preparing Promtail directories..."
mkdir -p "${PROMTAIL_CONFIG_DIR}"
mkdir -p "${PROMTAIL_POSITIONS_DIR}"

chown -R promtail:promtail "${PROMTAIL_POSITIONS_DIR}"
chmod 750 "${PROMTAIL_POSITIONS_DIR}"

# -----------------------------------------------------------------------------
# 7. Create Promtail configuration
# -----------------------------------------------------------------------------
echo "==> Writing Promtail configuration..."

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

if id promtail >/dev/null 2>&1; then
  chown root:root "${PROMTAIL_CONFIG_FILE}"
fi

chmod 644 "${PROMTAIL_CONFIG_FILE}"

# -----------------------------------------------------------------------------
# 8. Create systemd unit for Promtail
# -----------------------------------------------------------------------------
echo "==> Creating systemd unit for Promtail..."

cat > /etc/systemd/system/promtail.service <<'EOF'
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

# -----------------------------------------------------------------------------
# 9. Enable and start Promtail
# -----------------------------------------------------------------------------
echo "==> Reloading systemd..."
systemctl daemon-reload

echo "==> Enabling and starting Promtail..."
systemctl enable --now promtail

# -----------------------------------------------------------------------------
# 10. Validate Promtail service
# -----------------------------------------------------------------------------
echo "==> Promtail service status:"
systemctl status promtail --no-pager || true
