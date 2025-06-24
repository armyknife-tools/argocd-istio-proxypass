#!/bin/bash

# Deploy traffic capture solution using ArgoCD
set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}ArgoCD Deployment for Traffic Capture Solution${NC}"
echo "=============================================="

# Check if argocd CLI is installed
if ! command -v argocd &> /dev/null; then
    echo -e "${RED}Error: argocd CLI not found${NC}"
    echo "Install with: brew install argocd"
    exit 1
fi

# Check if logged in to ArgoCD
if ! argocd account get-user-info &> /dev/null; then
    echo -e "${YELLOW}Not logged in to ArgoCD${NC}"
    echo ""
    echo "To login:"
    echo "1. Port forward: kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
    echo "2. Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    echo "3. Login: argocd login localhost:8080 --username admin"
    exit 1
fi

# Get current context
CONTEXT=$(kubectl config current-context)
echo -e "${GREEN}✓ Connected to cluster: $CONTEXT${NC}"

# Check namespaces
echo -e "\n${BLUE}Checking namespaces...${NC}"
for ns in traffic-capture-dev traffic-capture-prod; do
    if kubectl get namespace $ns &> /dev/null; then
        echo -e "${GREEN}✓ Namespace $ns exists${NC}"
    else
        echo -e "${RED}✗ Namespace $ns not found${NC}"
        exit 1
    fi
done

# Check if istio-system exists for prod global routing
if ! kubectl get namespace istio-system &> /dev/null; then
    echo -e "${YELLOW}Warning: istio-system namespace not found (needed for production global routing)${NC}"
fi

# Update Git repository URL
echo -e "\n${YELLOW}IMPORTANT: Update Git repository URL in application manifests${NC}"
echo "Current repository: https://github.com/armyknife-tools/argocd-istio-proxypass"
read -p "Enter your Git repository URL: " REPO_URL

if [ -z "$REPO_URL" ]; then
    echo -e "${RED}Error: Git repository URL is required${NC}"
    exit 1
fi

# Update application manifests with repo URL
sed -i.bak "s|https://github.com/armyknife-tools/argocd-istio-proxypass|$REPO_URL|g" apps/*.yaml
rm -f apps/*.yaml.bak

echo -e "${GREEN}✓ Updated repository URL${NC}"

# Create ArgoCD project (optional)
echo -e "\n${BLUE}Creating ArgoCD project...${NC}"
kubectl apply -f apps/appproject.yaml || echo "Project might already exist"

# Deploy applications
echo -e "\n${BLUE}Deploying ArgoCD applications...${NC}"

# Deploy dev environment
echo "Deploying dev environment..."
kubectl apply -f apps/traffic-capture-dev.yaml
echo -e "${GREEN}✓ Dev application created${NC}"

# Deploy prod environment
echo "Deploying prod environment..."
kubectl apply -f apps/traffic-capture-prod.yaml
echo -e "${GREEN}✓ Prod application created${NC}"

# Wait for sync
echo -e "\n${BLUE}Waiting for applications to sync...${NC}"
echo "This may take a few minutes..."

# Sync dev
argocd app sync traffic-capture-dev --timeout 300
argocd app wait traffic-capture-dev --health --timeout 300

# Sync prod (manual by default)
echo -e "\n${YELLOW}Production sync is manual by default${NC}"
read -p "Sync production now? (y/n): " sync_prod
if [ "$sync_prod" == "y" ]; then
    argocd app sync traffic-capture-prod --timeout 300
    argocd app wait traffic-capture-prod --health --timeout 300
fi

# Show status
echo -e "\n${BLUE}Application Status:${NC}"
argocd app list | grep traffic-capture

echo -e "\n${GREEN}✓ Deployment complete!${NC}"
echo ""
echo "Access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Open: https://localhost:8080"
echo ""
echo "View applications:"
echo "  argocd app get traffic-capture-dev"
echo "  argocd app get traffic-capture-prod"
echo ""
echo "Test deployments:"
echo "  # Dev (namespace routing, 100% sampling)"
echo "  kubectl exec -it deployment/test-client -c client -n traffic-capture-dev -- curl -s http://example-app/"
echo "  kubectl exec -it deployment/test-client -c client -n traffic-capture-dev -- curl -s http://traffic-collector:9000/stats | jq"
echo ""
echo "  # Prod (global routing, 0.1% sampling)"
echo "  kubectl exec -it deployment/test-client -c client -n traffic-capture-prod -- /test-unknown-app.sh"
echo ""
echo -e "${YELLOW}Note: Production uses global routing via istio-system VirtualService${NC}"
echo "All services in the mesh will be captured (at 0.1% sampling rate)"