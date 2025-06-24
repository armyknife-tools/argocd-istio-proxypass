#!/bin/bash
# Quick setup to get runners working

set -e

echo "=== Quick Setup for GitHub Actions Runners ==="

NAMESPACE="actions-runner-system"

# 1. Ensure namespace exists
if ! kubectl get namespace $NAMESPACE 2>/dev/null; then
  kubectl create namespace $NAMESPACE
fi

# 2. Create GitHub token secret if missing
if ! kubectl get secret controller-manager -n $NAMESPACE 2>/dev/null; then
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Please set GITHUB_TOKEN environment variable"
    exit 1
  fi
  kubectl create secret generic controller-manager \
    -n $NAMESPACE \
    --from-literal=github_token="${GITHUB_TOKEN}"
fi

# 3. Install ARC if not installed
if ! helm list -n $NAMESPACE | grep -q "^arc"; then
  echo "Installing actions-runner-controller..."
  
  helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
  helm repo update
  
  # Use latest stable version
  helm install arc actions-runner-controller/actions-runner-controller \
    --namespace $NAMESPACE \
    --set authSecret.create=false \
    --set authSecret.name=controller-manager \
    --set webhook.enabled=false \
    --wait
fi

# 4. Wait for controller
echo "Waiting for controller..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=actions-runner-controller \
  -n $NAMESPACE --timeout=60s || true

# 5. Create RunnerDeployment
echo "Creating runners..."
kubectl apply -f - <<EOF
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: github-runner
  namespace: $NAMESPACE
spec:
  replicas: 2
  template:
    spec:
      repository: armyknife-tools/argocd-istio-proxypass
      labels:
        - self-hosted
        - linux
      
      # Environment variables
      env:
      - name: RUNNER_FEATURE_FLAG_EPHEMERAL
        value: "true"
EOF

# 6. Apply permissions workaround
echo "Applying permissions..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-runner-permissions
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-runner-permissions
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: github-runner-permissions
subjects:
- kind: ServiceAccount
  name: default
  namespace: $NAMESPACE
EOF

echo -e "\n✅ Quick setup complete!"
kubectl get pods -n $NAMESPACE