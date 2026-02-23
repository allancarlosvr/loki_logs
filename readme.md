# Loki Log Centralization – PoC (Rocky Linux + LXD)

## Overview

This Proof of Concept implements **Grafana Loki** as a centralized log aggregation system aligned with the internal architecture requirements:

- Loki server hosted on Prometheus node (per site)
- Storage on `/logdata`
- RPM-based installation (RHEL / Rocky compliant)
- Systemd-managed service
- LXD container deployment
- Network exposure for LAN/browser access

---

## Environment

| Component | Value |
|------------|--------|
| OS | Rocky Linux 9 |
| Deployment | LXD container (`loki01`) |
| Installation Method | Official RPM from GitHub |
| Storage Path | `/logdata/loki` |
| Service Manager | systemd |
| Network Exposure | LXD proxy device |

---

# 1️⃣ Install Loki (Latest Stable RPM)

## Query latest release and install x86_64 RPM (excluding canary builds)

```bash
# Query latest release tag
LOKI_LATEST_RELEASE=$(curl -s https://api.github.com/repos/grafana/loki/releases/latest \
| grep -Po '"tag_name":\s*"\K[^"]+')

# Get correct x86_64 RPM (exclude canary builds)
LOKI_RPM_URL=$(curl -s https://api.github.com/repos/grafana/loki/releases/latest \
| grep browser_download_url \
| grep 'loki-[0-9].*x86_64\.rpm"' \
| grep -v canary \
| cut -d '"' -f4)

```bash
echo "Installing Loki from: $LOKI_RPM_URL"

curl -L -o loki.rpm "$LOKI_RPM_URL"
dnf install -y ./loki.rpm
```

# 2️⃣ Prepare /logdata Storage

Loki storage must use the local /logdata partition.

```bash
mkdir -p /logdata/loki/{chunks,tsdb,wal,compactor,rules}
chown -R loki:loki /logdata/loki
chmod -R 750 /logdata/loki
```
Optional validation:

```bash
sudo -u loki bash -lc 'touch /logdata/loki/.write_test && rm -f /logdata/loki/.write_test'
```

# 3️⃣ Configure Loki

## 3.1 Default RPM Configuration

The RPM installs a default configuration file:
`/etc/loki/config.yml`

Instead of modifying the vendor file directly, we created a dedicated custom configuration file.

## 3.2 Copy Default Configuration

```bash
cp -a /etc/loki/config.yml /etc/loki/loki.yml
chown loki:loki /etc/loki/loki.yml
```
This ensures we start from a version-compatible configuration template.

## 3.3 Modify loki.yml to Use /logdata

Edit: `/etc/loki/loki.yml`

Key changes:
* Change path_prefix to /logdata/loki
* Update filesystem storage directories
* Configure TSDB storage paths
* Enable WAL under /logdata/loki/wal
* Disable pattern_ingester (optional for PoC)

Final configuration:

```yaml
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
```
# 4️⃣ Apply Systemd Override

By default, Loki service uses:
* `/etc/loki/config.yml`

We override it to use: 
* `/etc/loki/loki.yml.`

Create override directory:

```bash
mkdir -p /etc/systemd/system/loki.service.d
```

Create override file:
```bash
cat > /etc/systemd/system/loki.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/loki -config.file=/etc/loki/loki.yml
EOF
```

Reload systemd:

```bash
systemctl daemon-reload
```

# 5️⃣ Start and Enable Loki

```bash
systemctl enable --now loki
systemctl status loki --no-pager
```

# 6️⃣ Verify Loki Health

Check readiness endpoint:

```bash
curl http://localhost:3100/ready
```

Expected output:
`ready`

Check listening ports:
```bash
ss -lntp | grep 3100
```

# 7️⃣ Expose Loki from LXD Container

Since Loki runs inside an LXD container (loki01), expose port 3100:

```bash
lxc config device add loki01 loki3100 proxy \
listen=tcp:0.0.0.0:3100 \
connect=tcp:127.0.0.1:3100
```

# 8️⃣ Access Loki from LAN / Windows Browser

Get host IP:
`ip a`

Access from browser:
`http://<HOST_IP>:3100/ready`

Example:
`http://192.168.1.1:3100/ready`

Expected result:
`ready`

# Current Status

* Loki installed via official RPM
* Default config copied to custom file
* Custom configuration applied
* `/logdata` storage configured
* WAL nabled
* TSDB storage configured
* Pattern ingester disabled
* Systemd override applied
* LXD proxy configured
* Accessible from host network
* Browser access confirmed

# Next Steps

* Install Promtail agent
* Script automated deployment (xCAT postscript)
* Add Loki as Grafana datasource
* Build dashboards for licensing logs