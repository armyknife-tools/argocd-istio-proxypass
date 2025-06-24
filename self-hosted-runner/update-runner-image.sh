#!/bin/bash
# Update runner to use an image with kubectl

echo "=== Updating Runner Image to Include kubectl ==="

NAMESPACE="actions-runner-system"

# Update the runner deployment to use an image that includes kubectl
echo "Updating runner deployment..."
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
      repository: armyknife-tools/argocd-istio-proxypass
      labels:
        - self-hosted
        - linux
      
      # Use runner image that includes kubectl
      image: summerwind/actions-runner:latest
      
      # Add kubectl and other tools
      dockerdWithinRunnerContainer: true
      
      # Volume mounts for kubectl config
      volumeMounts:
      - name: kube-config
        mountPath: /home/runner/.kube
        readOnly: true
      
      volumes:
      - name: kube-config
        secret:
          secretName: runner-kube-config
          optional: true
      
      # Environment variables
      env:
      - name: RUNNER_FEATURE_FLAG_EPHEMERAL
        value: "true"
      
      # Resources
      resources:
        limits:
          cpu: "2"
          memory: "4Gi"
        requests:
          cpu: "1"
          memory: "2Gi"
EOF

echo "Waiting for runners to update..."
sleep 10
kubectl get pods -n $NAMESPACE

echo ""
echo "If kubectl is still not available, we'll need to create a custom runner image."