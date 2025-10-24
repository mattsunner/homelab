# Homelab - GitOps K8s Cluster

A production-ready Kubernetes homelab cluster managed via GitOps with ArgoCD, secured by Tailscale, and accessible at `mattsunner.com` domain.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Deployed Services](#deployed-services)
- [DNS Configuration](#dns-configuration)
- [Repository Structure](#repository-structure)
- [Managing Applications](#managing-applications)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [Security](#security)
- [Contributing](#contributing)

## Overview

The homelab implements a lightweight Kubernetes cluster using K3s with full GitOps automation via ArgoCD. All infrastructure and applications are defined as code, enabling declarative configuration management and automated deployments.

**Current Status:** OPERATIONAL

- **Cluster:** K3s v1.33.5+k3s1
- **GitOps:** ArgoCD managing all infrastructure components

## Architecture

### Network Architecture

```
Browser (Tailscale device)
    ↓
DNS: *.mattsunner.com 
    ↓
Tailscale Private Network 
    ↓
MetalLB Load Balancer
    ↓
NGINX Ingress Controller 
    ↓
Kubernetes Services
    ↓
Application Pods
```

### Core Components

| Component | Version | Namespace | Status |
|-----------|---------|-----------|--------|
| K3s | v1.33.5+k3s1 | - | Running |
| ArgoCD | stable | argocd | Running |
| NGINX Ingress | latest | ingress-nginx | Running |
| MetalLB | latest | metallb-system | Running |
| cert-manager | v1.13.2 | cert-manager | Running |
| Longhorn | v1.7.2 | longhorn-system | Running |
| PostgreSQL | 16-alpine | postgres | Running |
| PgAdmin | latest | postgres | Running |
| Heimdall | latest | heimdall | Running |
| Kube-Prometheus-Stack | v55.5.0 | monitoring | Running |
| HashiCorp Vault | 1.17 | vault | Running |

## Quick Start

**For existing clusters:** If the cluster is already running, you can skip to [Managing Applications](#managing-applications).

**For new installations:**

```bash
# Clone the repository
git clone https://github.com/mattsunner/homelab.git
cd homelab

# Run the bootstrap script (requires sudo)
chmod +x ./bootstrap.sh
sudo ./bootstrap.sh

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Browse to https://localhost:8080
# Login: admin
# Password: (displayed after bootstrap)

# Alternatively, access via ingress (after DNS setup)
# https://argocd.mattsunner.com
```

## Prerequisites

### Hardware Requirements

- Linux server (tested on Ubuntu/Debian)
- Minimum 2GB RAM
- 20GB available disk space
- Network connectivity (I currently am using a hardwired connection to machine)

### Software Requirements

- Ubuntu 20.04+ or Debian 11+
- `curl` installed
- `sudo` access
- Tailscale installed and authenticated ([tailscale.com](https://tailscale.com))

### External Services

1. **Cloudflare Account** (for DNS management)
   - Domain registered and added to Cloudflare
   - API token with DNS edit permissions

2. **Tailscale Account** (for private network access)
   - Tailscale installed on server and client devices
   - Server authenticated to your tailnet

3. **GitHub Account** (optional, for forking)
   - Fork this repository if you want to manage your own homelab

## Installation

### Step 1: Prepare the Server

```bash
# Install Tailscale (if not already installed)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Verify Tailscale IP
tailscale ip -4  # Note this IP for DNS configuration
```

### Step 2: Clone and Bootstrap

```bash
# Clone the repository
git clone https://github.com/mattsunner/homelab.git
cd homelab

# Make bootstrap script executable
chmod +x bootstrap.sh bootstrap/*.sh

# Run the bootstrap (installs K3s and ArgoCD)
sudo ./bootstrap.sh
```

The bootstrap script will:
1. Install K3s with Traefik and ServiceLB disabled
2. Configure kubectl for your user
3. Install ArgoCD in the `argocd` namespace
4. Display the initial admin password
5. Deploy the root ArgoCD application

### Step 3: Configure Cloudflare API Token

```bash
# Create Cloudflare API token secret for cert-manager
# Get your API token from: https://dash.cloudflare.com/profile/api-tokens
# Required permissions: Zone:DNS:Edit

kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN
```

### Step 4: Install cert-manager (Manual Step)

Due to CRD timing issues with ArgoCD, cert-manager must be installed manually:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/cert-manager -n cert-manager

# Apply the ClusterIssuer
kubectl apply -f infrastructure/cert-manager/cluster-issuer.yaml

# Verify ClusterIssuer is ready
kubectl get clusterissuer letsencrypt-prod
```

### Step 5: Install MetalLB (Manual Step)

MetalLB is partially managed by ArgoCD but requires initial manual setup:

```bash
# Apply MetalLB configuration
kubectl apply -f infrastructure/metallb/metallb.yaml

# Verify MetalLB is running
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

### Step 6: Install Longhorn Storage (Manual Step)

Longhorn provides persistent storage for stateful applications:

```bash
# Install Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.2/deploy/longhorn.yaml

# Wait for Longhorn to be ready (3-5 minutes)
kubectl get pods -n longhorn-system -w

# Verify StorageClass was created
kubectl get storageclass longhorn
```

### Step 7: Create PostgreSQL Secrets

Create secrets for PostgreSQL and PgAdmin before deploying:

```bash
# Create PostgreSQL credentials
kubectl create namespace postgres
kubectl create secret generic postgresql-secret \
  --namespace postgres \
  --from-literal=postgres-user=postgres \
  --from-literal=postgres-password=$(openssl rand -base64 32)

# Create PgAdmin credentials
kubectl create secret generic pgadmin-secret \
  --namespace postgres \
  --from-literal=pgadmin-email=admin@mattsunner.com \
  --from-literal=pgadmin-password=$(openssl rand -base64 24)

# Save passwords for later use!
echo "PostgreSQL password:"
kubectl get secret postgresql-secret -n postgres -o jsonpath='{.data.postgres-password}' | base64 -d
echo ""
echo "PgAdmin password:"
kubectl get secret pgadmin-secret -n postgres -o jsonpath='{.data.pgadmin-password}' | base64 -d
echo ""
```

### Step 8: Configure DNS in Cloudflare

Add A records in Cloudflare DNS pointing to your Tailscale IP:

| Name | Type | Content | Proxy Status | TTL |
|------|------|---------|--------------|-----|
| home | A | TailscaleIP | DNS only | Auto |
| argocd | A | TailscaleIP | DNS only | Auto |
| longhorn | A | TailscaleIP | DNS only | Auto |
| pgadmin | A | TailscaleIP | DNS only | Auto |
| grafana | A | TailscaleIP | DNS only | Auto |
| prometheus | A | TailscaleIP | DNS only | Auto |
| alertmanager | A | TailscaleIP | DNS only | Auto |
| vault | A | TailscaleIP | DNS only | Auto |

**Important:** Ensure "Proxy status" is set to "DNS only" (grey cloud icon), NOT proxied (orange cloud).

### Step 9: Verify Deployment

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Check ArgoCD applications
kubectl get applications -n argocd

# Check ingress resources
kubectl get ingress --all-namespaces

# Check certificates
kubectl get certificate --all-namespaces
```

### Step 10: Access Services

From any Tailscale-connected device:

- **Heimdall Dashboard:** https://home.mattsunner.com
- **ArgoCD UI:** https://argocd.mattsunner.com
- **Longhorn Storage UI:** https://longhorn.mattsunner.com
- **PgAdmin:** https://pgadmin.mattsunner.com
- **Grafana:** https://grafana.mattsunner.com
- **Prometheus:** https://prometheus.mattsunner.com
- **AlertManager:** https://alertmanager.mattsunner.com
- **HashiCorp Vault:** https://vault.mattsunner.com

## Deployed Services

### Heimdall Dashboard

**URL:** https://home.mattsunner.com

A centralized dashboard for accessing all homelab services.

**Configuration:**
- Namespace: `heimdall`
- Image: `lscr.io/linuxserver/heimdall:latest`
- Storage: `emptyDir` (ephemeral - consider upgrading to persistent volume)

### ArgoCD

**URL:** https://argocd.mattsunner.com

GitOps continuous delivery tool managing all cluster applications.

**Default Credentials:**
- Username: `admin`
- Password: Retrieve with:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
  ```

### Longhorn Storage

**URL:** https://longhorn.mattsunner.com

Distributed block storage system providing persistent volumes for stateful applications.

**Features:**
- Persistent storage for PostgreSQL, PgAdmin, and other stateful apps
- Volume snapshots and backups
- StorageClass: `longhorn` (default)
- Single-replica configuration (suitable for single-node cluster)

**Installation:** Manual (like cert-manager), ingress managed by ArgoCD

### PostgreSQL Database

**Internal Access:** `postgresql-lb.postgres.svc.cluster.local:5432`

Shared PostgreSQL 16 instance for homelab applications.

**Configuration:**
- Namespace: `postgres`
- Image: `postgres:16-alpine`
- Storage: 10GB Longhorn persistent volume
- User: `postgres`
- Credentials stored in `postgresql-secret`

**Retrieve Password:**
```bash
kubectl get secret postgresql-secret -n postgres \
  -o jsonpath='{.data.postgres-password}' | base64 -d
```

**Creating Application Databases:**
```sql
-- Connect via PgAdmin or kubectl exec
CREATE DATABASE myapp_db;
CREATE USER myapp_user WITH PASSWORD 'strong_password';
GRANT ALL PRIVILEGES ON DATABASE myapp_db TO myapp_user;
```

**Connection String for Apps:**
```
Host: postgresql-lb.postgres.svc.cluster.local
Port: 5432
Database: <your_db_name>
User: <your_db_user>
Password: <your_password>
```

### PgAdmin

**URL:** https://pgadmin.mattsunner.com

Web-based PostgreSQL administration interface.

**Configuration:**
- Namespace: `postgres`
- Storage: 2GB Longhorn persistent volume
- Pre-configured server connection to PostgreSQL

**Login Credentials:**
```bash
# Email
kubectl get secret pgadmin-secret -n postgres \
  -o jsonpath='{.data.pgadmin-email}' | base64 -d

# Password
kubectl get secret pgadmin-secret -n postgres \
  -o jsonpath='{.data.pgadmin-password}' | base64 -d
```

### Monitoring Stack (Kube-Prometheus-Stack)

**Grafana:** https://grafana.mattsunner.com
**Prometheus:** https://prometheus.mattsunner.com
**AlertManager:** https://alertmanager.mattsunner.com

**Grafana Credentials:**
- Username: `admin`
- Password: Retrieve with:
  ```bash
  kubectl get secret -n monitoring kube-prometheus-stack-grafana \
    -o jsonpath="{.data.admin-password}" | base64 --decode
  ```

### HashiCorp Vault

**URL:** https://vault.mattsunner.com

Secrets management and secure storage for sensitive data.

**Configuration:**
- Namespace: `vault`
- Image: `hashicorp/vault:1.17`
- Storage: 10GB Longhorn persistent volume (file storage backend)
- Deployment: StatefulSet with 1 replica

**Security:**
- Runs as non-root user (UID 1000)
- Memory locking disabled (`disable_mlock = true`)
- Health probes configured for sealed/uninitialized states

**Initial Setup:**
After deployment, initialize and unseal Vault:
```bash
# Initialize (run once, save output securely!)
kubectl exec -n vault vault-0 -- vault operator init

# Unseal (run after each pod restart with 3 of 5 keys)
kubectl exec -n vault vault-0 -- vault operator unseal <key-1>
kubectl exec -n vault vault-0 -- vault operator unseal <key-2>
kubectl exec -n vault vault-0 -- vault operator unseal <key-3>

# Check status
kubectl exec -n vault vault-0 -- vault status
```

**Access:**
- Login with root token from initialization
- **Important:** Store unseal keys and root token securely offline

## DNS Configuration

All DNS is managed through Cloudflare with the following pattern:

1. **Create A Record** pointing to your Tailscale IP
2. **Disable Cloudflare Proxy** (set to "DNS only")
3. **Update Ingress Manifest** to include the new hostname
4. **Let cert-manager automatically provision TLS certificate** via DNS-01 challenge

### Adding a New Service

Example for adding `service.mattsunner.com`:

1. Add DNS record in Cloudflare:
   ```
   Name: service
   Type: A
   Content: TailscaleIP
   Proxy: DNS only
   ```

2. Update your ingress resource:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: my-service
     namespace: my-namespace
     annotations:
       cert-manager.io/cluster-issuer: "letsencrypt-prod"
   spec:
     ingressClassName: nginx
     tls:
     - hosts:
       - service.mattsunner.com
       secretName: service-tls
     rules:
     - host: service.mattsunner.com
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: my-service
               port:
                 number: 80
   ```

## Repository Structure

```
homelab/
├── README.md                       # This file
├── bootstrap.sh                    # Main bootstrap orchestrator
├── bootstrap/
│   ├── k3s-install.sh             # K3s installation script
│   └── argocd-install.sh          # ArgoCD installation script
└── infrastructure/
    ├── argocd/
    │   ├── root-app.yaml          # ArgoCD root application (App of Apps pattern)
    │   └── applications.yaml      # All child application definitions
    ├── nginx-ingress/
    │   └── deployment.yaml        # NGINX Ingress HelmChart CRD
    ├── metallb/
    │   └── metallb.yaml           # MetalLB IPAddressPool and L2Advertisement
    ├── cert-manager/
    │   ├── install.yaml           # cert-manager installation manifest (reference)
    │   └── cluster-issuer.yaml    # Let's Encrypt ClusterIssuer with Cloudflare
    ├── longhorn/
    │   └── ingress.yaml           # Longhorn UI ingress (Longhorn itself installed manually)
    └── apps/
        ├── argocd/
        │   └── ingress.yaml       # ArgoCD ingress resource
        ├── heimdall/
        │   └── deployment.yaml    # Heimdall deployment, service, and ingress
        ├── postgres/
        │   ├── README.md          # PostgreSQL setup documentation
        │   ├── namespace.yaml     # Postgres namespace
        │   ├── postgresql-statefulset.yaml  # PostgreSQL StatefulSet and services
        │   ├── pgadmin-deployment.yaml      # PgAdmin deployment and PVC
        │   └── pgadmin-ingress.yaml         # PgAdmin ingress
        ├── monitoring/
        │   └── monitoring-app.yaml # Kube-Prometheus-Stack Helm application
        └── vault/
            └── deployment.yaml     # HashiCorp Vault StatefulSet, services, and ingress
```

## Managing Applications

### Adding a New Application

1. **Create application manifests** in `infrastructure/apps/<app-name>/`

2. **Define ArgoCD application** in `infrastructure/argocd/applications.yaml`:
   ```yaml
   ---
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: argocd
   spec:
     project: infrastructure
     source:
       repoURL: https://github.com/mattsunner/homelab.git
       targetRevision: main
       path: infrastructure/apps/my-app
     destination:
       server: https://kubernetes.default.svc
       namespace: my-app
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```

3. **Commit and push** to the repository:
   ```bash
   git add infrastructure/
   git commit -m "Add my-app application"
   git push
   ```

4. **ArgoCD will automatically sync** and deploy the application

### Modifying Existing Applications

Simply edit the manifest files and commit:

```bash
git add infrastructure/apps/<app-name>/
git commit -m "Update <app-name> configuration"
git push
```

ArgoCD will detect changes and sync automatically.

### Removing an Application

1. **Delete the application definition** from `infrastructure/argocd/applications.yaml`
2. **Commit and push:**
   ```bash
   git commit -am "Remove <app-name>"
   git push
   ```

ArgoCD will automatically prune the application if `prune: true` is set.

## Troubleshooting

### Common Issues

#### 1. ArgoCD Application Stuck in "Progressing"

```bash
# Check application status
kubectl describe application <app-name> -n argocd

# Check ArgoCD controller logs
kubectl logs -n argocd deployment/argocd-application-controller

# Manually sync application
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

#### 2. Certificate Not Issuing

```bash
# Check certificate status
kubectl describe certificate <cert-name> -n <namespace>

# Check certificate request
kubectl get certificaterequest -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

```

#### 3. Ingress Not Routing Traffic

```bash
# Check ingress resource
kubectl get ingress -n <namespace>
kubectl describe ingress <ingress-name> -n <namespace>

# Check NGINX ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Check LoadBalancer IP assignment
kubectl get svc -n ingress-nginx
```

#### 4. DNS Not Resolving

```bash
# Verify Tailscale IP
tailscale ip -4

# Test DNS resolution
dig home.mattsunner.com
nslookup home.mattsunner.com

# Check Cloudflare DNS settings (ensure proxy is disabled)
```

### Useful Commands

```bash
# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Restart a deployment
kubectl rollout restart deployment/<name> -n <namespace>

# Port-forward to a service
kubectl port-forward svc/<service-name> -n <namespace> <local-port>:<remote-port>

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Get Grafana admin password
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

## Maintenance

### Updating K3s

```bash
# Check current version
kubectl version

# Update K3s (example for upgrading to latest)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644" sh -

# Verify update
kubectl get nodes
```

### Updating ArgoCD

```bash
# Update ArgoCD to latest stable
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for rollout
kubectl rollout status deployment/argocd-server -n argocd
```

## Security

### Current Security Posture

**Network Isolation:** Tailscale provides zero-trust network access
**TLS Encryption:** All traffic encrypted via Let's Encrypt certificates
**Private IPs:** DNS points to non-routable Tailscale IP (100.x.x.x)
**No Public Exposure:** No ports open to internet
**Secret Management:** Sensitive data stored as Kubernetes secrets, not in Git

### Secrets Management

**Never commit secrets to Git!** All sensitive data should be:

1. Created manually via `kubectl create secret`
2. Or managed via external secret management (e.g., Sealed Secrets, External Secrets Operator)

**Current secrets (created manually):**
- `cloudflare-api-token` in `cert-manager` namespace
- `argocd-initial-admin-secret` in `argocd` namespace (auto-generated)
- `kube-prometheus-stack-grafana` in `monitoring` namespace (auto-generated)

### Testing Changes

Before committing changes to production:

```bash
# Validate Kubernetes manifests
kubectl apply --dry-run=client -f infrastructure/apps/<app-name>/

# Validate ArgoCD application
kubectl apply --dry-run=server -f infrastructure/argocd/applications.yaml
```
---

**Last Updated:** October 24, 2025
**Cluster Version:** K3s v1.33.5+k3s1
**ArgoCD Version:** Stable (latest)
