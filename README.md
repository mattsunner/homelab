# Homelab

This repository manages the infrastructure, Kubernetes configuration, and application deployments for a personal homelab environment. It is built using Infrastructure as Code (IaC) principles and powered by Ansible, K3s, FluxCD, and SOPS for secret management.

---

## Purpose

This homelab serves as a self-hosted environment for learning and practicing core cloud engineering and DevOps skills, including:
- Kubernetes operations and GitOps workflows
- Infrastructure automation with Ansible
- Containerization and application deployment
- Monitoring and observability
- Secure configuration and secret management 
- Cloud-native best practices in a controlled lab setup

---

## Architecture Overview

- **Ubuntu Server**: Bare-metal host OS running on a single-node machine (HP Elitedesk 800 G2)
- **K3s**: Lightweight Kubernetes distribution
- **FluxCD**: GitOps operator for syncing infrastructure and apps from this repository
- **Ansible**: Remote provisioning and configuration management
- **Tailscale**: VPN for secure remote access
- **SOPS**: For encrypting Kubernetes Secrets in Git

---

## Repository Structure

```
homelab/
├── ansible/                        # Infrastructure provisioning
│   ├── inventory/                 # Host inventory (Tailscale IPs)
│   ├── playbooks/                 # Ansible playbooks for K3s, setup, hardening
│   └── group_vars/                # Optional per-group vars
├── flux/                          # GitOps configuration
│   ├── clusters/                  # Cluster-scoped manifests
│   │   └── k3s/
│   ├── apps/                      # Applications and workloads
│   │   ├── monitoring/
│   │   └── workloads/
│   └── secrets/                   # Pre-wired for SOPS usage
│       └── k3s/
│           ├── sops-secret.enc.yaml
│           ├── age-key.txt       # (gitignored)
│           └── kustomization.yaml
├── scripts/                       # Bootstrap automation
│   └── bootstrap.sh
├── Makefile                       # Common workflow commands
└── README.md
```

---

## Usage

### Prerequisites
- Tailscale access to the homelab server
- SSH key authentication to the server
- [`flux` CLI](https://fluxcd.io/flux/installation/)
- [`ansible`](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- Optional (for secrets): [`sops`](https://github.com/mozilla/sops) and [`age`](https://github.com/FiloSottile/age)

### 1. Bootstrap the Environment
From your **dev machine**:
```bash
make bootstrap
```

This will:
- Run Ansible to install packages and K3s on the server
- Retrieve the kubeconfig
- Bootstrap FluxCD from this repo

### 2. Modify or Add Workloads
Make changes under `flux/apps/` and commit:
```bash
make apps
```

Flux will automatically pick up the changes and apply them to the cluster.

### 3. Add Secrets (SOPS)
When you're ready to encrypt secrets:
```bash
age-keygen -o flux/secrets/k3s/age-key.txt
sops --encrypt --age <public-key> plaintext.yaml > sops-secret.enc.yaml
```

Create the decryption secret in the cluster:
```bash
flux create secret age flux-age-key   --namespace=flux-system   --age-key-file=flux/secrets/k3s/age-key.txt
```

---

## Security Notes

- Do **not** commit private keys or unencrypted secrets.
- `age-key.txt` is excluded from Git via `.gitignore`.
- Placeholder encrypted secret (`sops-secret.enc.yaml`) is safe but should be replaced for production scenarios.
- All ingress and monitoring services are exposed only via Tailscale.

---

## Roadmap

- [x] Ubuntu + Tailscale + OpenSSH setup
- [x] Ansible-based K3s provisioning
- [x] FluxCD GitOps bootstrap
- [x] Pre-wire SOPS for encrypted secrets
- [ ] Add CI pipeline for container builds
- [ ] Deploy a sample app (Go or Python-based)
- [ ] Install monitoring stack (Prometheus + Grafana via Helm)
- [ ] Add automated backup strategy (Restic + Rclone)

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

