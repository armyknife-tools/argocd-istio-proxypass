#!/bin/bash
# Quick deployment script for self-hosted runner

set -e

echo "=== Deploying Self-Hosted Runner ==="

NAMESPACE="actions-runner-system"

# Check for PAT
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Please set GITHUB_TOKEN environment variable"
    echo "export GITHUB_TOKEN=ghp_your_token_here"
    exit 1
fi

# Run the setup
./setup-runner.sh

# Apply additional RBAC if needed
echo ""
echo "Checking RBAC permissions..."
# The setup-runner-correct.sh should handle basic RBAC, but we can add custom if needed

# Show status
echo ""
echo "=== Runner Status ==="
kubectl get runners -n $NAMESPACE
echo ""
kubectl get pods -n $NAMESPACE

echo ""
echo "✅ Self-hosted runner deployed!"
echo ""
echo "To use it, update your workflow to:"
echo '  runs-on: [self-hosted, linux]'
echo ""
echo "Then trigger with:"
echo "gh workflow run deploy-self-hosted.yml --repo=armyknife-tools/argocd-istio-proxypass -f environment=dev -f namespace=test"