#!/bin/bash

# Script to install ArgoCD in the cluster
set -euo pipefail

ARGOCD_VERSION="stable"
ARGOCD_NAMESPACE="argocd"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}Installing ArgoCD for GitOps Deployment${NC}"
echo "========================================"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

# Check cluster connection
echo -e "${BLUE}Checking cluster connection...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

CLUSTER_CONTEXT=$(kubectl config current-context)
echo -e "${GREEN}✓ Connected to cluster: $CLUSTER_CONTEXT${NC}"

# Check if ArgoCD is already installed
if kubectl get namespace $ARGOCD_NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}ArgoCD namespace already exists${NC}"
    read -p "Reinstall ArgoCD? (y/n): " reinstall
    if [ "$reinstall" != "y" ]; then
        echo "Skipping ArgoCD installation"
        echo ""
        echo "To access existing ArgoCD:"
        echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
        echo "  Open: https://localhost:8080"
        exit 0
    fi
    kubectl delete namespace $ARGOCD_NAMESPACE --wait=true
fi

# Create namespace
echo -e "\n${BLUE}Creating ArgoCD namespace...${NC}"
kubectl create namespace $ARGOCD_NAMESPACE

# Install ArgoCD
echo -e "\n${BLUE}Installing ArgoCD ${ARGOCD_VERSION}...${NC}"
kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

# Wait for deployment
echo -e "\n${BLUE}Waiting for ArgoCD to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n $ARGOCD_NAMESPACE
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n $ARGOCD_NAMESPACE
kubectl wait --for=condition=available --timeout=300s deployment/argocd-redis -n $ARGOCD_NAMESPACE
kubectl wait --for=condition=available --timeout=300s deployment/argocd-dex-server -n $ARGOCD_NAMESPACE 2>/dev/null || true

echo -e "${GREEN}✓ ArgoCD installed successfully!${NC}"

# Get initial admin password
echo -e "\n${BLUE}Getting ArgoCD admin password...${NC}"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Create ArgoCD CLI installation instructions
echo -e "\n${BOLD}ArgoCD Access Information:${NC}"
echo "=========================="
echo -e "${YELLOW}Username:${NC} admin"
echo -e "${YELLOW}Password:${NC} $ARGOCD_PASSWORD"
echo ""
echo -e "${BOLD}To access ArgoCD UI:${NC}"
echo "1. Start port forwarding:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "2. Open browser:"
echo "   https://localhost:8080"
echo ""
echo -e "${BOLD}To install ArgoCD CLI:${NC}"
echo "# MacOS"
echo "brew install argocd"
echo ""
echo "# Linux"
echo "curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
echo "chmod +x /usr/local/bin/argocd"
echo ""
echo -e "${BOLD}To login with CLI:${NC}"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
echo "argocd login localhost:8080 --username admin --password '$ARGOCD_PASSWORD' --insecure"

# Save credentials
echo -e "\n${BLUE}Saving credentials to argocd-credentials.txt...${NC}"
cat > argocd-credentials.txt <<EOF
ArgoCD Credentials
==================
URL: https://localhost:8080 (with port-forward)
Username: admin
Password: $ARGOCD_PASSWORD

Port Forward Command:
kubectl port-forward svc/argocd-server -n argocd 8080:443

CLI Login:
argocd login localhost:8080 --username admin --password '$ARGOCD_PASSWORD' --insecure
EOF

echo -e "${GREEN}✓ Credentials saved to argocd-credentials.txt${NC}"

# Optional: Change service to LoadBalancer for external access
echo ""
read -p "Expose ArgoCD with LoadBalancer? (y/n): " expose_lb
if [ "$expose_lb" == "y" ]; then
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
    echo -e "${YELLOW}Waiting for LoadBalancer IP...${NC}"
    sleep 10
    EXTERNAL_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    if [ "$EXTERNAL_IP" != "pending" ] && [ ! -z "$EXTERNAL_IP" ]; then
        echo -e "${GREEN}✓ ArgoCD accessible at: https://$EXTERNAL_IP${NC}"
    else
        echo -e "${YELLOW}LoadBalancer IP still pending. Check with:${NC}"
        echo "kubectl get svc argocd-server -n argocd"
    fi
fi

echo -e "\n${GREEN}✓ ArgoCD installation complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Start port forwarding: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "2. Login to UI: https://localhost:8080"
echo "3. Apply ArgoCD applications: kubectl apply -f apps/"