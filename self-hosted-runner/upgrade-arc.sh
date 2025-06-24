#!/bin/bash
# Upgrade actions-runner-controller to latest version

echo "=== Upgrading Actions Runner Controller ==="

NAMESPACE="actions-runner-system"

# First, remove the workaround
echo "1. Removing workaround..."
kubectl delete clusterrolebinding github-runner-default-sa 2>/dev/null || true

# Uninstall current version
echo -e "\n2. Uninstalling current version..."
helm uninstall arc -n $NAMESPACE

# Wait for cleanup
echo "Waiting for cleanup..."
sleep 10

# Re-run setup with latest version
echo -e "\n3. Running setup with latest version..."
cd "$(dirname "$0")"
./setup-runner.sh

echo -e "\n✅ Upgrade complete!"