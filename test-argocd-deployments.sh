#!/bin/bash

# Test both ArgoCD deployments
set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}Testing ArgoCD Deployments${NC}"
echo "=========================="

# Test Dev Environment (Namespace routing)
echo -e "\n${YELLOW}1. Testing DEV Environment (Namespace Routing)${NC}"
echo "Namespace: traffic-capture-dev"
echo "Expected: Only captures traffic within the namespace"
echo ""

# Check pods
echo "Checking pods..."
kubectl get pods -n traffic-capture-dev

# Get sampling rate
DEV_RATE=$(kubectl get configmap proxy-config -n traffic-capture-dev -o jsonpath='{.data.sampling_rate}' 2>/dev/null || echo "not found")
echo -e "\nSampling rate: ${YELLOW}$DEV_RATE${NC} (should be 1.0 for dev)"

# Test capture in dev namespace
echo -e "\n${BLUE}Testing traffic capture in dev...${NC}"
kubectl exec deployment/test-client -c client -n traffic-capture-dev -- curl -s http://example-app/ >/dev/null 2>&1 || echo "No example-app in dev"

# Create a test service in dev
echo "Creating test service in dev namespace..."
kubectl run test-dev-app --image=hashicorp/http-echo:0.2.3 -n traffic-capture-dev -- -text="Dev namespace test" 2>/dev/null || true
kubectl expose pod test-dev-app --port=80 --target-port=5678 -n traffic-capture-dev 2>/dev/null || true

sleep 5

# Test the service
kubectl exec deployment/test-client -c client -n traffic-capture-dev -- curl -s http://test-dev-app/ 2>/dev/null || echo "Service not ready"

# Check captures
DEV_STATS=$(kubectl exec deployment/test-client -c client -n traffic-capture-dev -- curl -s http://traffic-collector:9000/stats 2>/dev/null || echo "{}")
echo -e "\nDev capture statistics:"
echo "$DEV_STATS" | jq '.' || echo "$DEV_STATS"

# Test cross-namespace (should NOT be captured in dev)
echo -e "\n${BLUE}Testing cross-namespace traffic (should NOT be captured)...${NC}"
kubectl exec deployment/test-client -c client -n traffic-capture-dev -- curl -s http://kubernetes.default.svc.cluster.local 2>/dev/null || true

echo -e "\n${GREEN}✓ Dev environment test complete${NC}"

# Test Prod Environment (Global routing)
echo -e "\n${YELLOW}2. Testing PROD Environment (Global Routing)${NC}"
echo "Namespace: traffic-capture-prod"
echo "Expected: Captures traffic from ALL namespaces (via istio-system VS)"
echo ""

# Check pods
echo "Checking pods..."
kubectl get pods -n traffic-capture-prod

# Get sampling rate
PROD_RATE=$(kubectl get configmap proxy-config -n traffic-capture-prod -o jsonpath='{.data.sampling_rate}' 2>/dev/null || echo "not found")
echo -e "\nSampling rate: ${YELLOW}$PROD_RATE${NC} (should be 0.001 for prod)"

# Check global VirtualService
echo -e "\n${BLUE}Checking global VirtualService in istio-system...${NC}"
kubectl get virtualservice -n istio-system global-traffic-capture 2>/dev/null || echo -e "${RED}Global VirtualService not found in istio-system!${NC}"

# Create test service in a different namespace
TEST_NS="test-traffic-capture"
echo -e "\n${BLUE}Creating test in separate namespace...${NC}"
kubectl create namespace $TEST_NS --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
kubectl label namespace $TEST_NS istio-injection=enabled --overwrite 2>/dev/null

# Create test app
kubectl run test-external-app --image=hashicorp/http-echo:0.2.3 -n $TEST_NS -- -text="External namespace test" 2>/dev/null || true
kubectl expose pod test-external-app --port=80 --target-port=5678 -n $TEST_NS 2>/dev/null || true

# Create test client in test namespace
kubectl run test-client-external --image=curlimages/curl:latest -n $TEST_NS -- sleep 3600 2>/dev/null || true

sleep 10

# Make request from external namespace (should be captured by global routing)
echo -e "\n${BLUE}Testing global capture from external namespace...${NC}"
echo "Making 100 requests to trigger 0.1% sampling..."
for i in {1..100}; do
    kubectl exec test-client-external -n $TEST_NS -- curl -s http://test-external-app/ >/dev/null 2>&1 || true
done

# Check if captured
PROD_STATS=$(kubectl exec deployment/test-client -c client -n traffic-capture-prod -- curl -s http://traffic-collector:9000/stats 2>/dev/null || echo "{}")
echo -e "\nProd capture statistics:"
echo "$PROD_STATS" | jq '.' || echo "$PROD_STATS"

# Look for captures from test namespace
echo -e "\n${BLUE}Checking for cross-namespace captures...${NC}"
kubectl exec deployment/test-client -c client -n traffic-capture-prod -- \
    curl -s http://traffic-collector:9000/query?limit=10 2>/dev/null | \
    jq -r '.[] | select(.headers."x-capture-namespace" == "test-traffic-capture") | {service: .destination.service, namespace: .headers."x-capture-namespace"}' 2>/dev/null || \
    echo "No cross-namespace captures found (might need more requests with 0.1% sampling)"

# Cleanup
echo -e "\n${BLUE}Cleaning up test resources...${NC}"
kubectl delete pod test-dev-app -n traffic-capture-dev --wait=false 2>/dev/null || true
kubectl delete service test-dev-app -n traffic-capture-dev --wait=false 2>/dev/null || true
kubectl delete namespace $TEST_NS --wait=false 2>/dev/null || true

echo -e "\n${GREEN}✓ All tests complete!${NC}"
echo ""
echo -e "${BOLD}Summary:${NC}"
echo "• Dev environment: Namespace-scoped routing (traffic-capture-dev only)"
echo "• Prod environment: Global routing (all namespaces via istio-system)"
echo ""
echo "To view ArgoCD applications:"
echo "  argocd app get traffic-capture-dev"
echo "  argocd app get traffic-capture-prod"