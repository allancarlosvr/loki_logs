# Loki Cluster Logging for HPC

Centralized log aggregation for HPC clusters using Grafana Loki and Promtail.

## Architecture

Compute Nodes → Promtail → Loki Server → Grafana

## Deployment Modes

### PoC Environment

Initial validation using LXD containers.

See:

docs/poc_lxd_environment.md

### HPC Cluster Deployment

Production architecture for cluster nodes.

Master node:
dc1clu0005-mstr

Compute nodes:
n01
n02
n03
n04
n05