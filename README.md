# Loki Log Centralization – HPC PoC (xCAT + Promtail)

## 📌 Overview

This project implements a centralized logging solution for an HPC cluster using:

- **Grafana Loki** (log storage)
- **Promtail** (log agent on compute nodes)
- **xCAT** (deployment and orchestration)

The goal is to enable scalable and structured log collection across compute nodes, with labels designed for HPC environments.

---

## 🏗️ Architecture

- **Master Node**
  - Loki server running on port `3100`
  - Receives logs from compute nodes

- **Compute Nodes (n01–n05)**
  - Promtail agent
  - Collects `/var/log/messages`
  - Pushes logs to Loki

---

## ⚙️ Environment

| Component        | Value |
|----------------|------|
| OS             | RHEL 8.6 |
| Cluster        | dc1 |
| Deployment     | xCAT |
| Promtail       | 3.5.6 (ZIP) |
| Loki           | RPM install |
| Network        | Internal cluster network |

---

## 🚀 Loki Setup (Master Node)

- Installed via official RPM
- Config file: `/etc/loki/loki.yml`
- Service: `systemctl enable --now loki`
- Validation: `curl http://localhost:3100/ready

## 🚀 Promtail Deployment (Compute Nodes)

### Installation Method

Promtail is deployed using:
- xCAT postscript
- Binary distributed manually (`xdcp`) or pre-staged
- No dependency on external internet (GitHub fallback optional)

#### Binary Installation

```bash
unzip /tmp/promtail.zip
install -m 0755 promtail-linux-amd64 /usr/bin/promtail
```

#### Configuration

- File: `/etc/promtail/config.yml`
- Example:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://dc1clu0005-mstr:3100/loki/api/v1/push

scrape_configs:
  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: <hostname>
          cluster: dc1
          role: compute
          env: prod
          __path__: /var/log/messages
```

- Systemd Service

```bash
[Unit]
Description=Promtail service
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/promtail -config.file /etc/promtail/config.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
```
xCAT Deployment

Promtail is deployed via postscript:

`/install/postscripts/KT/promtail_postscript.sh`

Execution example:

```bash
xdcp n03 /install/postscripts/KT/promtail_postscript.sh /tmp/promtail_postscript.sh
xdcp n03 /install/postscripts/KT/promtail_postscript.sh /tmp/promtail_postscript.sh
```

## 🧠 HPC Label Strategy

Labels were designed for cluster observability:

| Label          | Description |
|----------------|-------------|
| job            | Log type (syslog) |
| host           | Node hostname |
| cluster        | Cluster identifier |
| role           | Node role (compute, master, login) |
| env            | Environment (prod, test, lab)   


