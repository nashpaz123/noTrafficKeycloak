#!/bin/bash

set -e

echo "=== Deploying Keycloak and Nginx Reverse Proxy ==="

# Check if minikube is running
if ! minikube status &> /dev/null; then
    echo "Error: Minikube is not running. Please run setup.sh first."
    exit 1
fi

# Set kubectl context to minikube
kubectl config use-context minikube

# Create namespace
echo "Creating namespace..."
kubectl create namespace keycloak-proxy --dry-run=client -o yaml | kubectl apply -f -

# Generate self-signed certificate
echo "Generating self-signed certificate..."
mkdir -p certs
if [ ! -f certs/tls.crt ] || [ ! -f certs/tls.key ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout certs/tls.key \
        -out certs/tls.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=keycloak.local"
    echo "Certificate generated"
else
    echo "Certificate already exists, skipping generation"
fi

# Create TLS secret
echo "Creating TLS secret..."
kubectl create secret tls keycloak-tls \
    --cert=certs/tls.crt \
    --key=certs/tls.key \
    -n keycloak-proxy \
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy Keycloak
echo "Deploying Keycloak..."
kubectl apply -f k8s/keycloak-deployment.yaml
kubectl apply -f k8s/keycloak-service.yaml

# Wait for Keycloak to be ready
echo "Waiting for Keycloak to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/keycloak -n keycloak-proxy

# Create nginx configuration
echo "Creating nginx configuration..."
if [ ! -f nginx.conf ]; then
    echo "Error: nginx.conf file not found"
    exit 1
fi
kubectl create configmap nginx-config \
    --from-file=nginx.conf=nginx.conf \
    -n keycloak-proxy \
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy Nginx reverse proxy
echo "Deploying Nginx reverse proxy..."
kubectl apply -f k8s/nginx-deployment.yaml
kubectl apply -f k8s/nginx-service.yaml

# Wait for nginx to be ready
echo "Waiting for Nginx to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/nginx-proxy -n keycloak-proxy

echo "=== Deployment complete ==="
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod --all -n keycloak-proxy --timeout=300s

echo ""
echo "=== Deployment Status ==="
kubectl get pods -n keycloak-proxy
kubectl get services -n keycloak-proxy

# Setup iptables port forwarding to make NodePorts accessible on host interface
echo ""
echo "=== Setting up port forwarding ==="
# Enable IP forwarding
echo "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null

MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"

# Function to setup iptables forwarding
setup_port_forward() {
    local HOST_PORT=$1
    local TARGET_IP=$2
    local TARGET_PORT=$3
    local HOST_IP=$(hostname -I | awk '{print $1}')
    
    # Check if PREROUTING rule already exists
    if sudo iptables -t nat -C PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT} 2>/dev/null; then
        echo "PREROUTING rule for $HOST_PORT already exists"
    else
        # Add PREROUTING rule for external traffic
        echo "Setting up PREROUTING rule for port $HOST_PORT -> ${TARGET_IP}:${TARGET_PORT}..."
        sudo iptables -t nat -A PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT}
    fi
    
    # Check if OUTPUT rule for localhost exists
    if sudo iptables -t nat -C OUTPUT -p tcp --dport $HOST_PORT -d 127.0.0.1 -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT} 2>/dev/null; then
        echo "OUTPUT rule for localhost ($HOST_PORT) already exists"
    else
        # Add OUTPUT rule for localhost
        echo "Setting up OUTPUT rule for localhost: $HOST_PORT -> ${TARGET_IP}:${TARGET_PORT}..."
        sudo iptables -t nat -A OUTPUT -p tcp --dport $HOST_PORT -d 127.0.0.1 -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT}
    fi
    
    # Check if OUTPUT rule for host IP exists
    if [ -n "$HOST_IP" ]; then
        if sudo iptables -t nat -C OUTPUT -p tcp --dport $HOST_PORT -d ${HOST_IP} -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT} 2>/dev/null; then
            echo "OUTPUT rule for host IP ($HOST_PORT) already exists"
        else
            # Add OUTPUT rule for host IP
            echo "Setting up OUTPUT rule for host IP ($HOST_IP): $HOST_PORT -> ${TARGET_IP}:${TARGET_PORT}..."
            sudo iptables -t nat -A OUTPUT -p tcp --dport $HOST_PORT -d ${HOST_IP} -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT}
        fi
    fi
    
    echo "Port forwarding configured for $HOST_PORT"
}

# Setup forwarding for HTTP and HTTPS NodePorts
setup_port_forward 30080 $MINIKUBE_IP 30080
setup_port_forward 30443 $MINIKUBE_IP 30443

echo ""
echo "Port forwarding setup complete. NodePorts should now be accessible on the host interface."
echo "You can now access Keycloak at https://localhost:30443 or http://<MINIKUBE_IP>:30443"
echo "or via minikube tunnel externally at https://<EC2_PUBLIC_IP>:30443"
