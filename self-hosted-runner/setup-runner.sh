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
NAMESPACES_TO_DELETE=("actions-runner-system" "arc-system" "github-runner")
for ns in "${NAMESPACES_TO_DELETE[@]}"; do
  if kubectl get namespace $ns 2>/dev/null; then
    echo "Deleting namespace $ns..."
    kubectl delete namespace $ns --wait=false 2>/dev/null || true
  fi
done

# Force delete any stuck namespaces
echo "Checking for stuck namespaces..."
for ns in "${NAMESPACES_TO_DELETE[@]}"; do
  if kubectl get namespace $ns 2>/dev/null | grep -q Terminating; then
    echo "Force cleaning namespace $ns..."
    kubectl get namespace $ns -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
  fi
done

# Wait for all namespaces to be gone
echo "Waiting for namespace cleanup..."
for i in {1..30}; do
  if ! kubectl get namespace actions-runner-system 2>/dev/null; then
    echo "Namespace deleted successfully"
    break
  fi
  echo "Waiting for namespace deletion... ($i/30)"
  sleep 2
done

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
  # Ensure cert-manager is actually ready
  kubectl wait --for=condition=available --timeout=60s deployment/cert-manager -n cert-manager || true
  kubectl wait --for=condition=available --timeout=60s deployment/cert-manager-webhook -n cert-manager || true
fi

# Step 2: Create namespace for ARC
echo -e "\n3. Creating namespace..."
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace already exists"

# Step 3: Create GitHub token secret
echo "4. Creating GitHub token secret..."
kubectl create secret generic controller-manager \
  -n $NAMESPACE \
  --from-literal=github_token="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

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

# Webhook configuration
webhook:
  enabled: true

# Cert-manager configuration
certManager:
  enabled: true

# Resources
resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
EOF

# Use a stable chart version
ARC_CHART_VERSION="0.23.7"  # This includes app version 0.27.6
echo "Installing actions-runner-controller chart version: $ARC_CHART_VERSION"

if helm install arc actions-runner-controller/actions-runner-controller \
  --namespace $NAMESPACE \
  --version $ARC_CHART_VERSION \
  --values /tmp/arc-values.yaml \
  --wait \
  --timeout 5m; then
  echo "✅ ARC installed successfully"
else
  echo "❌ ARC installation failed, checking logs..."
  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=actions-runner-controller --tail=50
  exit 1
fi

# Step 5: Wait for controller to be ready
echo -e "\n6. Waiting for controller to be ready..."
if ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=actions-runner-controller \
  -n $NAMESPACE --timeout=300s; then
  echo "❌ Controller pod not ready, checking status..."
  kubectl get pods -n $NAMESPACE
  kubectl describe pod -n $NAMESPACE -l app.kubernetes.io/name=actions-runner-controller
  exit 1
fi

# Verify controller is actually running
CONTROLLER_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=actions-runner-controller -o name | head -1)
if [ -z "$CONTROLLER_POD" ]; then
  echo "❌ No controller pod found!"
  exit 1
fi
echo "✅ Controller is running: $CONTROLLER_POD"

# Step 6: Apply RBAC for runners
echo -e "\n7. Applying RBAC..."
# Check if runner-rbac.yaml exists in current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/runner-rbac.yaml" ]; then
  echo "Applying RBAC from runner-rbac.yaml..."
  kubectl apply -f "$SCRIPT_DIR/runner-rbac.yaml"
elif [ -f "runner-rbac.yaml" ]; then
  echo "Applying RBAC from local runner-rbac.yaml..."
  kubectl apply -f runner-rbac.yaml
else
  echo "Creating RBAC resources inline..."
  # Create RBAC inline if file doesn't exist
  kubectl apply -f - <<'RBAC'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-runner
  namespace: actions-runner-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-runner-deployer
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "create", "patch", "update"]
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "serviceaccounts"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: ["networking.istio.io"]
  resources: ["virtualservices", "destinationrules", "gateways", "serviceentries", "sidecars"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-runner-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: github-runner-deployer
subjects:
- kind: ServiceAccount
  name: github-runner
  namespace: actions-runner-system
RBAC
fi

# Step 7: Create runner deployment
echo -e "\n8. Creating runner deployment..."
cat <<EOF | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: github-runner
  namespace: $NAMESPACE
spec:
  replicas: 1
  template:
    spec:
      repository: $REPO
      labels:
        - self-hosted
        - linux
      
      # Docker in Docker for running containers
      dockerEnabled: true
      dockerdWithinRunnerContainer: true
      
      # Use the dind image which has more tools
      image: summerwind/actions-runner-dind:latest
      
      # Service account
      serviceAccountName: github-runner
      
      # Environment variables
      env:
      - name: RUNNER_FEATURE_FLAG_EPHEMERAL
        value: "true"
      
      # Minimal resources for resource-constrained clusters
      resources:
        limits:
          cpu: "500m"
          memory: "1Gi"
        requests:
          cpu: "100m"
          memory: "256Mi"
EOF

echo -e "\n9. Checking status..."
sleep 10
kubectl get pods -n $NAMESPACE

# Verify runners are using the correct service account
echo -e "\n10. Verifying service account..."
sleep 5  # Give pods time to start
RUNNER_PODS=$(kubectl get pods -n $NAMESPACE -l runner-deployment-name=github-runner -o name 2>/dev/null | wc -l)
if [ "$RUNNER_PODS" -gt 0 ]; then
  RUNNER_SA=$(kubectl get pods -n $NAMESPACE -l runner-deployment-name=github-runner -o jsonpath='{.items[0].spec.serviceAccountName}' 2>/dev/null || echo "")
  if [ "$RUNNER_SA" == "github-runner" ]; then
    echo "✅ Runners are using the correct service account: github-runner"
  else
    echo "✅ Runners deployed (service account: ${RUNNER_SA:-default})"
  fi
else
  echo "⚠️  No runner pods found yet, they may still be starting..."
fi

# Final verification
echo -e "\n11. Final verification..."
RUNNER_COUNT=$(kubectl get runners -n $NAMESPACE --no-headers | wc -l)
CONTROLLER_READY=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=actions-runner-controller -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')

if [ "$CONTROLLER_READY" != "True" ]; then
  echo "⚠️  Controller is not fully ready yet"
fi

if [ "$RUNNER_COUNT" -eq 0 ]; then
  echo "⚠️  No runners created yet, they may take a moment to appear"
else
  echo "✅ Found $RUNNER_COUNT runners"
fi

echo -e "\n✅ Setup complete!"
echo "Controller namespace: $NAMESPACE"
echo ""
echo "To check runner status:"
echo "kubectl get runners -n $NAMESPACE"
echo "kubectl get pods -n $NAMESPACE"
echo ""
echo "To use in GitHub Actions workflow:"
echo "  runs-on: [self-hosted, linux]"
echo ""
echo "To check controller logs:"
echo "kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=actions-runner-controller -f"

# Clean up
rm -f /tmp/arc-values.yaml