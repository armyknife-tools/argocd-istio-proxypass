#!/bin/bash
# Fix permissions for runners using default service account

echo "=== Fixing Runner Permissions ==="

NAMESPACE="actions-runner-system"

# Since the runners are using the default service account, 
# we'll grant permissions to it temporarily
echo "Granting permissions to default service account..."

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-runner-default-sa
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: github-runner-deployer
subjects:
- kind: ServiceAccount
  name: default
  namespace: $NAMESPACE
EOF

echo ""
echo "✅ Permissions granted to default service account in $NAMESPACE"
echo ""
echo "Note: This is a workaround for the current version of actions-runner-controller."
echo "In production, you should upgrade to a newer version that properly supports serviceAccountName."