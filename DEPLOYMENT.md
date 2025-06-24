# Automated Istio Traffic Capture Deployment

## Problem Solved

When deploying via ArgoCD to dynamic namespaces, the namespace needs `istio-injection=enabled` label for the solution to work. This is now automated.

## How It Works

1. **ArgoCD PreSync Hook**: A Kubernetes Job runs before any other resources
2. **Automatic Labeling**: The job labels the current namespace with `istio-injection=enabled`
3. **Self-Cleaning**: The job deletes itself after completion
4. **No Manual Steps**: Fully automated deployment

## Deployment via ArgoCD UI

1. Create new application
2. Set repository: `https://github.com/armyknife-tools/argocd-istio-proxypass`
3. Set path: `overlays/dev`
4. Set namespace: YOUR-NAMESPACE
5. Set kustomize namespace: YOUR-NAMESPACE (must match)
6. Enable "Create Namespace"
7. Deploy

**That's it! No manual steps required.**

## How the Automation Works

```yaml
# The PreSync hook runs this before deployment:
kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite
```

The job:
- Detects its own namespace dynamically
- Labels the namespace
- Requires minimal RBAC permissions (only namespace labeling)
- Cleans up after itself

## Verification

After deployment, verify:
```bash
# Check namespace label
kubectl get namespace YOUR-NAMESPACE --show-labels | grep istio-injection

# Check pods have sidecars
kubectl get pods -n YOUR-NAMESPACE -o custom-columns=NAME:.metadata.name,CONTAINERS:.spec.containers[*].name
```

You should see:
- example-app and test-client with `istio-proxy` sidecars
- passthrough-proxy and traffic-collector WITHOUT sidecars