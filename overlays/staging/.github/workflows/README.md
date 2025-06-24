# GitHub Actions CI/CD Workflows

This directory contains automated CI/CD workflows for the Istio Traffic Capture solution.

## Workflows

### 1. Deploy Traffic Capture (`deploy-traffic-capture.yml`)

**Purpose**: Automated deployment to any environment via ArgoCD

**Triggers**:
- Push to `main` branch (auto-deploys to dev)
- Manual workflow dispatch with parameters

**Features**:
- Creates ArgoCD application
- Deploys to specified namespace
- Verifies deployment health
- Runs basic connectivity tests
- Supports dev/staging/prod environments

**Required Secrets**:
- `ARGOCD_SERVER`: ArgoCD server URL
- `ARGOCD_TOKEN`: ArgoCD authentication token
- `KUBECONFIG`: Base64-encoded kubeconfig for cluster access

**Usage**:
```bash
# Manual deployment via GitHub UI
# Go to Actions → Deploy Traffic Capture → Run workflow
# Fill in:
# - Environment: dev/staging/prod
# - Namespace: your-namespace
# - Cluster: (optional, defaults to https://kubernetes.default.svc)
```

### 2. Test Traffic Capture (`test-traffic-capture.yml`)

**Purpose**: Automated testing for pull requests

**Triggers**:
- Pull requests to `main` branch
- Manual workflow dispatch

**Features**:
- Creates temporary test namespace
- Deploys and tests traffic capture
- Verifies sensitive data masking
- Checks sidecar configuration
- Cleans up after tests

**Test Coverage**:
- Basic traffic capture functionality
- Sensitive data masking (SSN, credit cards)
- Sidecar injection verification
- Response capture and timing

### 3. Cleanup Namespaces (`cleanup-namespaces.yml`)

**Purpose**: Clean up old test namespaces and ArgoCD apps

**Triggers**:
- Daily at 2 AM UTC
- Manual workflow dispatch

**Features**:
- Finds test namespaces older than 24 hours
- Deletes orphaned ArgoCD applications
- Supports dry-run mode
- Configurable age threshold

**Patterns Cleaned**:
- `traffic-capture-test-*`
- `traffic-capture-pr-*`
- `traffic-capture-auto-*`

## Setup Instructions

1. **Create GitHub Secrets**:
   ```bash
   # ArgoCD Server URL (without https://)
   gh secret set ARGOCD_SERVER -b "argocd.example.com"
   
   # ArgoCD Token (create via ArgoCD UI/CLI)
   gh secret set ARGOCD_TOKEN -b "your-argocd-token"
   
   # Kubeconfig (base64 encoded)
   kubectl config view --minify --flatten | base64 | gh secret set KUBECONFIG
   ```

2. **Configure Environments** (optional):
   - Go to Settings → Environments
   - Create: `dev`, `staging`, `prod`
   - Add protection rules as needed
   - Add environment-specific secrets

3. **Enable Workflows**:
   - Go to Actions tab
   - Enable GitHub Actions if not already enabled

## Workflow Examples

### Automated Deployment on Push
```yaml
# When you push to main, it automatically:
# 1. Creates namespace: traffic-capture-auto-{commit-sha}
# 2. Deploys to dev environment
# 3. Runs verification tests
```

### Manual Production Deployment
```yaml
# Via GitHub UI:
# 1. Go to Actions → Deploy Traffic Capture
# 2. Click "Run workflow"
# 3. Select:
#    - Environment: prod
#    - Namespace: traffic-capture-prod
# 4. Review and approve (if protection rules enabled)
```

### PR Testing
```yaml
# When you create a PR:
# 1. Creates namespace: traffic-capture-pr-{pr-number}
# 2. Deploys and tests changes
# 3. Reports results in PR comments
# 4. Cleans up namespace after tests
```

## Best Practices

1. **Namespace Naming**:
   - Dev: `traffic-capture-dev`
   - Staging: `traffic-capture-staging`
   - Prod: `traffic-capture-prod`
   - Test: `traffic-capture-test-{identifier}`

2. **Environment Protection**:
   - Add required reviewers for prod
   - Use environment secrets for sensitive data
   - Enable deployment branches restriction

3. **Monitoring**:
   - Check Actions tab for workflow status
   - Review deployment summaries
   - Monitor ArgoCD for sync status

## Troubleshooting

### Common Issues

1. **Namespace already exists**:
   - The workflow handles existing namespaces
   - It will update the ArgoCD app if it exists

2. **Istio injection not working**:
   - The automated job labels the namespace
   - Check job logs in ArgoCD/Kubernetes

3. **ArgoCD sync fails**:
   - Check ArgoCD UI for detailed errors
   - Verify repository access
   - Check kustomize paths

### Debug Commands
```bash
# Check workflow runs
gh run list --workflow=deploy-traffic-capture.yml

# View workflow logs
gh run view <run-id> --log

# Check ArgoCD app status
argocd app get traffic-capture-<namespace>

# Check namespace labels
kubectl get namespace <namespace> --show-labels
```