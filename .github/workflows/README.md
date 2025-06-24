# GitHub Actions Workflows

This directory contains CI/CD workflows for the Istio Traffic Capture solution.

## Available Workflows

### 1. Deploy Traffic Capture (`deploy-traffic-capture.yml`)
- **Trigger**: Push to main or manual dispatch
- **Purpose**: Deploy to dev/staging/prod environments via ArgoCD
- **Features**: Automated namespace labeling, health checks, verification

### 2. Test Traffic Capture (`test-traffic-capture.yml`)
- **Trigger**: Pull requests or manual dispatch
- **Purpose**: Run automated tests on PR changes
- **Features**: Creates temporary namespace, runs tests, cleans up

### 3. Quick Test (`quick-test.yml`)
- **Trigger**: Manual dispatch only
- **Purpose**: Quick deployment and testing
- **Features**: Simple one-click test deployment

## Required Secrets

Configure these in your GitHub repository settings:

```bash
# ArgoCD server (without https://)
ARGOCD_SERVER: argocd.example.com

# ArgoCD authentication token
ARGOCD_TOKEN: <your-argocd-token>

# Base64 encoded kubeconfig
KUBECONFIG: <base64-encoded-kubeconfig>
```

## Usage Examples

### Manual Deployment
1. Go to Actions → Deploy Traffic Capture
2. Click "Run workflow"
3. Fill in:
   - Environment: dev/staging/prod
   - Namespace: your-namespace
   - Cluster: (optional)

### Quick Test
1. Go to Actions → Quick Test
2. Click "Run workflow"
3. Enter namespace name
4. View results in the workflow run

## Key Features

- **Automated Istio Injection**: PreSync hook automatically labels namespace
- **No Manual Steps**: Fully automated deployment
- **Multi-Environment**: Support for dev, staging, and production
- **Health Verification**: Automatic health checks and sidecar verification
- **Test Coverage**: Validates traffic capture and data masking