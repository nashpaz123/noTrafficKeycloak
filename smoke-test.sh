#!/bin/bash -x

set -e

echo "=== Running Smoke Tests ==="

# Check if minikube is running
if ! minikube status &> /dev/null; then
    echo "Error: Minikube is not running."
    exit 1
fi

# Set kubectl context
kubectl config use-context minikube

# Get minikube IP
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"

# Get NodePort for HTTPS
HTTPS_PORT=$(kubectl get service nginx-proxy -n keycloak-proxy -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
HTTP_PORT=$(kubectl get service nginx-proxy -n keycloak-proxy -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

echo "Nginx HTTPS NodePort: $HTTPS_PORT"
echo "Nginx HTTP NodePort: $HTTP_PORT"

# Test 1: Check if pods are running
echo ""
echo "Test 1: Checking pod status..."
KEYCLOAK_READY=$(kubectl get pods -n keycloak-proxy -l app=keycloak -o jsonpath='{.items[0].status.phase}')
NGINX_READY=$(kubectl get pods -n keycloak-proxy -l app=nginx-proxy -o jsonpath='{.items[0].status.phase}')

if [ "$KEYCLOAK_READY" != "Running" ]; then
    echo "FAIL: Keycloak pod is not running (status: $KEYCLOAK_READY)"
    exit 1
fi

if [ "$NGINX_READY" != "Running" ]; then
    echo "FAIL: Nginx pod is not running (status: $NGINX_READY)"
    exit 1
fi

echo "PASS: All pods are running"

# Test 2: Check if services are created
echo ""
echo "Test 2: Checking service status..."
KEYCLOAK_SVC=$(kubectl get service keycloak -n keycloak-proxy -o jsonpath='{.spec.type}')
NGINX_SVC=$(kubectl get service nginx-proxy -n keycloak-proxy -o jsonpath='{.spec.type}')

if [ "$KEYCLOAK_SVC" != "ClusterIP" ]; then
    echo "FAIL: Keycloak service is not ClusterIP (type: $KEYCLOAK_SVC)"
    exit 1
fi

if [ "$NGINX_SVC" != "NodePort" ]; then
    echo "FAIL: Nginx service is not NodePort (type: $NGINX_SVC)"
    exit 1
fi

echo "PASS: Services are correctly configured"

# Test 3: Check if Keycloak is accessible internally
echo ""
echo "Test 3: Testing internal Keycloak connectivity..."
HTTP_CODE=$(kubectl run test-pod --image=curlimages/curl:latest --rm -i --restart=Never -n keycloak-proxy -- \
    curl -s -o /dev/null -w "%{http_code}" http://keycloak.keycloak-proxy.svc.cluster.local:8080 2>/dev/null || echo "000")
if echo "$HTTP_CODE" | grep -qE "200|302|401"; then
    echo "PASS: Keycloak is accessible internally (HTTP code: $HTTP_CODE)"
else
    echo "FAIL: Keycloak is not accessible internally (HTTP code: $HTTP_CODE)"
    exit 1
fi

# Test 4: Check if HTTP redirects to HTTPS
echo ""
echo "Test 4: Testing HTTP to HTTPS redirect..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k http://$MINIKUBE_IP:$HTTP_PORT/ || echo "000")
if [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "308" ]; then
    echo "PASS: HTTP correctly redirects to HTTPS"
else
    echo "WARN: HTTP redirect test returned code: $HTTP_CODE (may be expected)"
fi

# Test 5: Check if HTTPS endpoint is accessible
echo ""
echo "Test 5: Testing HTTPS endpoint..."
HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k https://$MINIKUBE_IP:$HTTPS_PORT/ || echo "000")
if [ "$HTTPS_CODE" = "200" ] || [ "$HTTPS_CODE" = "302" ] || [ "$HTTPS_CODE" = "401" ]; then
    echo "PASS: HTTPS endpoint is accessible (HTTP code: $HTTPS_CODE)"
else
    echo "FAIL: HTTPS endpoint returned code: $HTTPS_CODE"
    exit 1
fi

# Test 6: Check if Keycloak login page is served
echo ""
echo "Test 6: Testing Keycloak login page..."
RESPONSE=$(curl -s -k https://$MINIKUBE_IP:$HTTPS_PORT/ | grep -i "keycloak\|sign in\|login" || echo "")
if [ -n "$RESPONSE" ]; then
    echo "PASS: Keycloak login page is accessible"
else
    echo "WARN: Could not verify Keycloak login page content (may still be loading)"
fi

# Final output
echo ""
echo "=== Smoke Tests Complete ==="
echo ""
echo "Access Keycloak at:"
echo "  HTTPS: https://$MINIKUBE_IP:$HTTPS_PORT"
echo ""
echo "For AWS EC2 instance, use:"
echo "  HTTPS: https://$(curl -s ifconfig.me || echo 'YOUR_EC2_PUBLIC_IP'):$HTTPS_PORT"
echo ""
echo "Note: You'll need to accept the self-signed certificate warning in your browser."
echo ""
echo "Default Keycloak credentials:"
echo "  Username: admin"
echo "  Password: admin"

