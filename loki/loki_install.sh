#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Loki installation script for HPC cluster master node
# Target node: dc1clu0005-mstr
# OS: RHEL / Rocky / Alma
# Storage: /logdata/loki
# -----------------------------------------------------------------------------

LOGDATA_BASE="/logdata/loki"
LOKI_CONFIG_DIR="/etc/loki"
LOKI_CONFIG_FILE="${LOKI_CONFIG_DIR}/loki.yml"
SYSTEMD_OVERRIDE_DIR="/etc/systemd/system/loki.service.d"
SYSTEMD_OVERRIDE_FILE="${SYSTEMD_OVERRIDE_DIR}/override.conf"

echo "==> Starting Loki installation..."

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
# 3. Detect latest stable Loki RPM URL
# -----------------------------------------------------------------------------
echo "==> Detecting latest Loki release..."

LOKI_RPM_URL=$(curl -s https://api.github.com/repos/grafana/loki/releases/latest \
  | grep browser_download_url \
  | grep 'loki-[0-9].*x86_64\.rpm"' \
  | grep -v canary \
  | cut -d '"' -f4)

if [[ -z "${LOKI_RPM_URL}" ]]; then
  echo "ERROR: Could not detect Loki RPM URL."
  exit 1
fi

echo "==> Loki RPM URL: ${LOKI_RPM_URL}"

# -----------------------------------------------------------------------------
# 4. Download and install Loki
# -----------------------------------------------------------------------------
TMP_RPM="/tmp/loki.rpm"

echo "==> Downloading Loki RPM..."
curl -L -o "${TMP_RPM}" "${LOKI_RPM_URL}"

echo "==> Installing Loki RPM..."
dnf install -y "${TMP_RPM}"

# -----------------------------------------------------------------------------
# 5. Prepare /logdata storage
# -----------------------------------------------------------------------------
echo "==> Preparing storage directories under ${LOGDATA_BASE} ..."
mkdir -p "${LOGDATA_BASE}"/{chunks,tsdb,tsdb-cache,wal,compactor,rules}

if id loki >/dev/null 2>&1; then
  chown -R loki:loki "${LOGDATA_BASE}"
else
  echo "WARNING: loki user not found yet. Ownership will be retried later."
fi

chmod -R 750 "${LOGDATA_BASE}"

# -----------------------------------------------------------------------------
# 6. Prepare custom Loki configuration
# -----------------------------------------------------------------------------
echo "==> Preparing custom Loki configuration..."

mkdir -p "${LOKI_CONFIG_DIR}"

if [[ -f "${LOKI_CONFIG_DIR}/config.yml" ]]; then
  cp -a "${LOKI_CONFIG_DIR}/config.yml" "${LOKI_CONFIG_FILE}"
else
  echo "WARNING: Default config.yml not found. Creating ${LOKI_CONFIG_FILE} from scratch."
  touch "${LOKI_CONFIG_FILE}"
fi

cat > "${LOKI_CONFIG_FILE}" <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: info

common:
  instance_addr: 127.0.0.1
  path_prefix: /logdata/loki
  replication_factor: 1
  storage:
    filesystem:
      chunks_directory: /logdata/loki/chunks
      rules_directory: /logdata/loki/rules
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /logdata/loki/chunks
  tsdb_shipper:
    active_index_directory: /logdata/loki/tsdb
    cache_location: /logdata/loki/tsdb-cache

ingester:
  wal:
    enabled: true
    dir: /logdata/loki/wal

compactor:
  working_directory: /logdata/loki/compactor

limits_config:
  retention_period: 14d

pattern_ingester:
  enabled: false
EOF

if id loki >/dev/null 2>&1; then
  chown loki:loki "${LOKI_CONFIG_FILE}"
fi

chmod 640 "${LOKI_CONFIG_FILE}"

# -----------------------------------------------------------------------------
# 7. Apply systemd override
# -----------------------------------------------------------------------------
echo "==> Applying systemd override..."
mkdir -p "${SYSTEMD_OVERRIDE_DIR}"

cat > "${SYSTEMD_OVERRIDE_FILE}" <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/loki -config.file=/etc/loki/loki.yml
EOF

# -----------------------------------------------------------------------------
# 8. Ensure ownership after package install
# -----------------------------------------------------------------------------
if id loki >/dev/null 2>&1; then
  chown -R loki:loki "${LOGDATA_BASE}"
fi

# -----------------------------------------------------------------------------
# 9. Reload systemd and start Loki
# -----------------------------------------------------------------------------
echo "==> Reloading systemd..."
systemctl daemon-reload

echo "==> Enabling and starting Loki..."
systemctl enable --now loki

# -----------------------------------------------------------------------------
# 10. Validate service
# -----------------------------------------------------------------------------
echo "==> Loki service status:"
systemctl status loki --no-pager || true

echo "==> Waiting a few seconds before readiness check..."
sleep 5

echo "==> Checking Loki readiness endpoint..."
if curl -fsS http://localhost:3100/ready >/dev/null 2>&1; then
  echo "SUCCESS: Loki is ready."
else
  echo "WARNING: Loki is not ready yet. Check:"
  echo "  systemctl status loki --no-pager"
  echo "  journalctl -u loki -n 100 --no-pager"
fi

echo "==> Installation finished."