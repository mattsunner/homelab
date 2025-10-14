#!/bin/bash

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --node-name homelab-01 \
  --cluster-init" sh -

until kubectl get nodes | grep -q " Ready"; do
  echo "Waiting for K3s to be ready..."
  sleep 5
done

echo "K3s cluster is ready!"
