# GitHub Actions Workflows

This directory contains the production CI/CD workflow for the Istio Traffic Capture solution using self-hosted runners.

## Production Workflow

### Deploy via Self-Hosted Runner (`deploy-self-hosted.yml`)
- **Trigger**: 
  - Push to main (auto-creates preview environment)
  - Manual dispatch (for dev/staging/prod deployments)
- **Purpose**: Deploy traffic capture solution via ArgoCD
- **Runner**: Self-hosted runner inside the Kubernetes cluster
- **Security**: No cluster credentials needed in GitHub

## How It Works

1. **Automatic Deployments**: Every push to main creates a preview environment with namespace `traffic-capture-auto-<commit-sha>`
2. **Manual Deployments**: Use workflow dispatch to deploy to specific environments (dev/staging/prod)
3. **ArgoCD Integration**: Creates ArgoCD applications for GitOps management
4. **Self-Hosted Runner**: Runs inside the cluster with proper RBAC permissions

## Usage

### Manual Deployment
1. Go to Actions → Deploy via Self-Hosted Runner
2. Click "Run workflow"
3. Fill in:
   - Environment: dev/staging/prod
   - Namespace: target namespace name

### Automatic Preview
- Just push to main branch
- A preview environment will be created automatically

## No Secrets Required!

This workflow uses a self-hosted runner inside the cluster, so:
- ✅ No KUBECONFIG needed
- ✅ No ARGOCD_TOKEN in GitHub secrets
- ✅ No cluster endpoints exposed
- ✅ Direct cluster access via service accounts