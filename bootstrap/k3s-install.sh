#!/bin/bash
set -e

echo "=== Installing K3s ==="

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --cluster-init" sh -

echo "✓ K3s service started"

# Set KUBECONFIG for this script
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Waiting for K3s to be ready..."

# Wait for node with proper config
counter=0
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  echo "Waiting... (${counter}s)"
  sleep 5
  counter=$((counter + 5))
  
  if [ $counter -gt 120 ]; then
    echo "ERROR: K3s not ready after 2 minutes"
    echo "Checking service status:"
    systemctl status k3s --no-pager
    echo ""
    echo "Last 20 log lines:"
    journalctl -u k3s -n 20 --no-pager
    exit 1
  fi
done

echo "✓ K3s cluster is ready!"
kubectl get nodes

# Set up kubectl for the user who ran sudo
if [ -n "$SUDO_USER" ]; then
  echo ""
  echo "Setting up kubectl for user $SUDO_USER..."
  SUDO_HOME=$(eval echo ~$SUDO_USER)
  mkdir -p "$SUDO_HOME/.kube"
  cp /etc/rancher/k3s/k3s.yaml "$SUDO_HOME/.kube/config"
  chown -R $SUDO_USER:$SUDO_USER "$SUDO_HOME/.kube"
  chmod 600 "$SUDO_HOME/.kube/config"
  echo "✓ kubectl configured for $SUDO_USER"
  echo ""
  echo "You can now run: kubectl get nodes"
fi
