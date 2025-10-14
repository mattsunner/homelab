#!/bin/bash
set -e

echo "=== Homelab K3s Bootstrap ==="

# Install K3s
echo "Installing K3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --cluster-init" sh -

# Wait for K3s service to be active
echo "Waiting for K3s service..."
until systemctl is-active --quiet k3s; do
  sleep 2
done
echo "✓ K3s service is active"

# Export kubeconfig for this script
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for node to be ready
echo "Waiting for node to be Ready..."
counter=0
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  printf "."
  sleep 5
  counter=$((counter + 5))
  
  if [ $counter -gt 120 ]; then
    echo ""
    echo "ERROR: Timeout waiting for node"
    sudo k3s kubectl get nodes
    journalctl -u k3s -n 30 --no-pager
    exit 1
  fi
done

echo ""
echo "✓ K3s cluster is ready!"
kubectl get nodes

# Configure kubectl for non-root user
if [ -n "$SUDO_USER" ]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  echo ""
  echo "Configuring kubectl for $SUDO_USER..."
  mkdir -p "$USER_HOME/.kube"
  cp /etc/rancher/k3s/k3s.yaml "$USER_HOME/.kube/config"
  chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.kube"
  chmod 600 "$USER_HOME/.kube/config"
  echo "✓ Done!"
  echo ""
  echo "Run as $SUDO_USER: kubectl get nodes"
else
  echo ""
  echo "To use kubectl, run:"
  echo "  mkdir -p ~/.kube"
  echo "  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config"
  echo "  sudo chown \$USER:\$USER ~/.kube/config"
fi

echo ""
echo "=== Bootstrap Complete ==="

