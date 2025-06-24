# Self-Hosted GitHub Runner Setup

This directory contains the setup for deploying a self-hosted GitHub Actions runner inside your Kubernetes cluster using actions-runner-controller. This is the most secure option for CI/CD in a public repository.

## Benefits

- **No exposed endpoints**: The runner runs inside your cluster
- **No credentials in GitHub**: No KUBECONFIG or cluster endpoints needed
- **Direct cluster access**: Can use kubectl and internal service names
- **Ephemeral runners**: Fresh environment for each job
- **Scalable**: Can run multiple runners in parallel

## Prerequisites

1. **GitHub Personal Access Token (PAT)**
   - Go to https://github.com/settings/tokens/new
   - Create a token with these permissions:
     - `repo` (full control)
     - `admin:org` (if using organization runners)
   - Save the token securely

2. **Helm 3** installed locally

3. **kubectl** access to your cluster

## Installation

1. **Set your GitHub PAT**:
   ```bash
   export GITHUB_TOKEN="ghp_your_token_here"
   ```

2. **Run the setup script**:
   ```bash
   cd self-hosted-runner
   chmod +x setup-runner.sh
   ./setup-runner.sh
   ```

3. **Verify runners are ready**:
   ```bash
   kubectl get runners -n actions-runner-system
   kubectl get pods -n actions-runner-system
   ```

4. **Apply additional RBAC if needed**:
   ```bash
   kubectl apply -f runner-rbac.yaml
   ```

## Using the Self-Hosted Runner

1. **Update your workflow** to use the self-hosted runner:
   ```yaml
   jobs:
     deploy:
       runs-on: [self-hosted, linux]
   ```

2. **Trigger the workflow**:
   ```bash
   gh workflow run deploy-self-hosted.yml \
     --repo=armyknife-tools/argocd-istio-proxypass \
     -f environment=dev \
     -f namespace=traffic-capture-test
   ```

## Architecture

```
GitHub Actions
     |
     v
Self-Hosted Runner (in cluster)
     |
     v
Direct kubectl access
     |
     v
Your workloads
```

## Security Features

1. **Ephemeral runners**: Each job gets a fresh runner pod
2. **RBAC controlled**: Limited permissions via ServiceAccount
3. **No external access needed**: Runner pulls jobs from GitHub
4. **Automated cleanup**: Completed runner pods are removed

## Monitoring

View runner logs:
```bash
kubectl logs -n actions-runner-system -l app.kubernetes.io/name=actions-runner-controller -f
```

Check runner status:
```bash
kubectl get runners -n actions-runner-system
```

## Scaling

To add more runners:
```bash
kubectl scale runnerdeployment github-runner -n actions-runner-system --replicas=5
```

## Troubleshooting

1. **Runners not registering**:
   - Check PAT token permissions
   - Verify repository name in setup
   - Check runner logs

2. **Jobs queued but not running**:
   - Ensure runner labels match workflow
   - Check runner pod status
   - Verify RBAC permissions

3. **Permission denied errors**:
   - Review runner-rbac.yaml
   - Check ServiceAccount is applied

## Cleanup

To remove the self-hosted runners:
```bash
helm uninstall arc -n actions-runner-system
kubectl delete namespace actions-runner-system
```