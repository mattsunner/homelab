#!/bin/bash
set -e

echo "=== Homelab K8s Bootstrap ==="

echo "Installing K3s..."
./bootstrap/k3s-install.sh

echo "Installing ArgoCD..."
./bootstrap/argocd-install.sh

echo "Deploying root ArgoCD application..."
kubectl apply -f infrastructure/argocd/root-app.yaml

echo "Waiting for ArgoCD to sync applications..."
sleep 10

echo "=== Bootstrap Complete ==="
echo "Access ArgoCD UI via:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then browse to https://localhost:8080"
echo ""
echo "Login: admin"
echo "Password: (see above)"
