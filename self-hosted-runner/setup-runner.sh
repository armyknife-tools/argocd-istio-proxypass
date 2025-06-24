#!/bin/bash
# Setup script for GitHub Actions Runner Controller (ARC)

set -e

echo "=== Setting up GitHub Actions Runner Controller ==="

# Check token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Please set GITHUB_TOKEN environment variable"
    echo "export GITHUB_TOKEN=ghp_your_token_here"
    exit 1
fi

# Configuration
NAMESPACE="actions-runner-system"
REPO="armyknife-tools/argocd-istio-proxypass"

# Clean up any previous installations
echo "1. Cleaning up previous installations..."
helm list -A | grep "^arc" | while read name namespace rest; do
  echo "Uninstalling $name from $namespace"
  helm uninstall $name -n $namespace 2>/dev/null || true
done

# Clean up old namespaces
kubectl delete namespace actions-runner-system --wait=false 2>/dev/null || true
kubectl delete namespace arc-system --wait=false 2>/dev/null || true
kubectl delete namespace github-runner --wait=false 2>/dev/null || true

# Wait for cleanup
echo "Waiting for cleanup..."
sleep 10

# Step 1: Ensure cert-manager is installed and ready
echo -e "\n2. Checking cert-manager..."
if ! kubectl get namespace cert-manager 2>/dev/null; then
  echo "Installing cert-manager..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
  echo "Waiting for cert-manager to be ready..."
  kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
  kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
  kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
  sleep 20  # Extra wait for webhooks
else
  echo "cert-manager already installed"
fi

# Step 2: Create namespace for ARC
echo -e "\n3. Creating namespace..."
kubectl create namespace $NAMESPACE

# Step 3: Create GitHub token secret
echo "4. Creating GitHub token secret..."
kubectl create secret generic controller-manager \
  -n $NAMESPACE \
  --from-literal=github_token="${GITHUB_TOKEN}"

# Step 4: Install ARC with proper configuration
echo -e "\n5. Installing actions-runner-controller..."

# Add the official Helm repository
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# Install with correct values
cat > /tmp/arc-values.yaml <<EOF
# GitHub authentication
authSecret:
  create: false
  name: controller-manager
  github_token: "github_token"

# Image configuration
image:
  repository: summerwind/actions-runner-controller
  tag: v0.27.6

# Webhook configuration
webhook:
  enabled: true

# Cert-manager configuration
certManager:
  enabled: true

# Metrics configuration  
metrics:
  serviceMonitor: false
  port: 8443

# Log level
logLevel: info

# Resources
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 100m
    memory: 128Mi
EOF

helm install arc actions-runner-controller/actions-runner-controller \
  --namespace $NAMESPACE \
  --version 0.22.0 \
  --values /tmp/arc-values.yaml \
  --wait

# Step 5: Wait for controller to be ready
echo -e "\n6. Waiting for controller to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=actions-runner-controller \
  -n $NAMESPACE --timeout=300s

# Step 6: Create runner deployment
echo -e "\n7. Creating runner deployment..."
cat <<EOF | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: github-runner
  namespace: $NAMESPACE
spec:
  replicas: 2
  template:
    spec:
      repository: $REPO
      labels:
        - self-hosted
        - linux
EOF

echo -e "\n8. Checking status..."
sleep 10
kubectl get pods -n $NAMESPACE

echo -e "\n✅ Setup complete!"
echo "Controller namespace: $NAMESPACE"
echo ""
echo "To check runner status:"
echo "kubectl get runners -n $NAMESPACE"
echo "kubectl get pods -n $NAMESPACE"
echo ""
echo "To use in GitHub Actions workflow:"
echo "  runs-on: [self-hosted, linux]"

# Clean up
rm -f /tmp/arc-values.yaml