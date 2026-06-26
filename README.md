# Dozzle on Kubernetes

Terraform configuration to deploy [Dozzle](https://dozzle.dev/) (a real-time Docker log viewer) to a Kubernetes cluster.

## Overview

This project provisions Dozzle in Kubernetes mode, allowing it to read logs from all pods cluster-wide via the Kubernetes API. It includes proper RBAC, TLS, and ingress configuration.

## Architecture

```
User → Ingress (Traefik) → Service → Dozzle Pod → Kubernetes API → Pod Logs
                                          ↑
                                   Service Account Auth
```

Components deployed:
- **Namespace**: `dozzle`
- **Service Account**: `dozzle-pod-viewer` with `ClusterRole`/`ClusterRoleBinding` for cluster-wide log access
- **Deployment**: `amir20/dozzle:v10.6.6` in Kubernetes mode
- **Service**: Exposes port 80 → 8080
- **Ingress**: TLS-enabled via Let's Encrypt and Traefik

## Quick Start

```bash
# Initialize Terraform
terraform init

# Plan and apply
terraform plan -out dozzle.plan
terraform apply dozzle.plan
```

## Documentation

For detailed documentation, see [`AGENTS.md`](AGENTS.md).

## Prerequisites

- Valid `~/.kube/config` pointing to the target cluster
- AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) for the S3 backend (Cloudflare R2)
- Traefik ingress controller installed
- cert-manager for TLS provisioning
- DNS record pointing `dozzle.darkroasted.vps-kinghost.net` to the cluster ingress

## License

See the project LICENSE file for details.
