# AGENTS.md - Dozzle Kubernetes Deployment

Terraform configuration for deploying [Dozzle](https://dozzle.dev/) (a real-time Docker log viewer) to a Kubernetes cluster with proper RBAC, TLS, and ingress.

## Project Overview

This repo contains Infrastructure-as-Code (IaC) to deploy Dozzle in Kubernetes mode. Dozzle is a web-based log viewer that can read logs from all pods cluster-wide when configured with appropriate RBAC permissions.

## Essential Commands

```bash
# Initialize Terraform (downloads providers)
terraform init

# Plan changes (outputs to dozzle.plan file)
terraform plan -out dozzle.plan

# Apply the planned changes
terraform apply dozzle.plan

# Destroy all resources (USE WITH CAUTION)
terraform destroy

# Format Terraform files
terraform fmt

# Validate configuration
terraform validate
```

## Project Structure

```
.
├── main.tf              # All Terraform resources (monolithic)
├── .terraform.lock.hcl  # Provider version lock file
├── .gitignore           # Excludes .terraform/, *.tfstate, *.plan
└── AGENTS.md            # This file
```

## Architecture

### Components Deployed

1. **Namespace**: `dozzle` - Isolated namespace for the deployment
2. **Service Account**: `dozzle-pod-viewer` - Dedicated SA for pod permissions
3. **ClusterRole**: `dozzle-log-reader` - Grants read access to:
   - pods, pods/log, nodes, events, namespaces (core API)
   - pods (metrics.k8s.io for resource metrics)
4. **ClusterRoleBinding**: Links the SA to the ClusterRole (cluster-wide access)
5. **Deployment**: Single replica running `amir20/dozzle:v10.6.6`
6. **Service**: Exposes port 80 → container port 8080
7. **Ingress**: Traefik ingress with Let's Encrypt TLS for `dozzle.darkroasted.vps-kinghost.net`

### Data Flow

```
User → Ingress (Traefik) → Service → Dozzle Pod → Kubernetes API → Pod Logs
                                           ↑
                                    Service Account Auth
```

## Configuration Details

### Terraform Backend

Uses S3-compatible backend (Cloudflare R2):
- Bucket: `tasknote`
- State file: `kubernetes/terraform.tfstate`
- Endpoint: `d17eb09b6bce2f90e16e800bb2a6baf9.r2.cloudflarestorage.com`

**Important**: The backend is pre-configured in `main.tf`. Do not modify without updating the remote state location.

### Dozzle Configuration

Environment variables set in the deployment:
- `DOZZLE_MODE=k8s` - Enables Kubernetes mode (reads from K8s API instead of Docker socket)
- `DOZZLE_LEVEL=info` - Log level

### Resource Limits

- Memory: 64Mi request / 128Mi limit
- CPU: 50m request / 200m limit

## RBAC Permissions

Dozzle requires **cluster-wide read access** to function. The ClusterRole grants:

```yaml
apiGroups: [""]
resources: ["pods", "pods/log", "nodes", "events", "namespaces"]
verbs: ["get", "list", "watch"]
```

This is intentional and required - Dozzle needs to discover and stream logs from all pods across all namespaces.

## Prerequisites

Before running `terraform apply`:

1. **Kubernetes cluster access**: `~/.kube/config` must be valid and pointing to the target cluster
2. **Terraform credentials**: Environment variables for S3 backend access:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
3. **Ingress controller**: Traefik must be installed in the cluster
4. **cert-manager**: Required for automatic TLS certificate provisioning
5. **DNS**: `dozzle.darkroasted.vps-kinghost.net` must resolve to the cluster ingress

## Common Operations

### View Dozzle Logs

```bash
kubectl logs -n dozzle deployment/dozzle
```

### Update Dozzle Version

Edit `main.tf` line 83:
```hcl
image = "amir20/dozzle:v<NEW_VERSION>"
```

Then plan and apply.

### Access Dozzle Locally

```bash
# Port-forward to access without ingress
kubectl port-forward -n dozzle svc/dozzle 8080:80
# Then open http://localhost:8080
```

## Important Gotchas

1. **ClusterRoleBinding is global**: The binding grants access across the entire cluster, not just the dozzle namespace. This is necessary for Dozzle to read logs from all pods.

2. **Backend credentials**: The S3 backend requires valid AWS credentials (even though it's Cloudflare R2). Ensure these are exported before running any terraform commands.

3. **State file location**: The state is stored remotely. Never run `terraform apply` from multiple locations simultaneously.

4. **Ingress annotations are Traefik-specific**: The ingress uses `kubernetes.io/ingress.class: traefik`. If your cluster uses a different ingress controller (nginx, etc.), update the annotations.

5. **No authentication**: Dozzle is deployed without authentication. Access is controlled at the ingress/network level. The exposed URL is public-facing with TLS.

## CI/CD Considerations

If setting up automation:
- Ensure `KUBE_CONFIG_PATH` or `~/.kube/config` is available
- Backend credentials must be provided as environment variables
- Run `terraform plan` in PRs, `terraform apply` on merge to main

## References

- [Dozzle Documentation](https://dozzle.dev/)
- [Dozzle GitHub](https://github.com/amir20/dozzle)
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
