#!/bin/bash -x

set -e

echo "=== Cleaning up Keycloak deployment ==="

# Check if minikube is running
if ! minikube status &> /dev/null; then
    echo "Minikube is not running. Nothing to clean up."
    exit 0
fi

# Set kubectl context
kubectl config use-context minikube

# Delete namespace (this will delete all resources)
echo "Deleting keycloak-proxy namespace..."
kubectl delete namespace keycloak-proxy --ignore-not-found=true

# Wait for namespace to be deleted
echo "Waiting for namespace deletion..."
kubectl wait --for=delete namespace/keycloak-proxy --timeout=60s 2>/dev/null || true

# Clean up local certificates
echo "Cleaning up local certificates..."
rm -rf certs

# Remove iptables port forwarding rules
echo "Removing iptables port forwarding rules..."
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "")
if [ -n "$MINIKUBE_IP" ]; then
    # Remove PREROUTING rules
    sudo iptables -t nat -D PREROUTING -p tcp --dport 30080 -j DNAT --to-destination ${MINIKUBE_IP}:30080 2>/dev/null || true
    sudo iptables -t nat -D PREROUTING -p tcp --dport 30443 -j DNAT --to-destination ${MINIKUBE_IP}:30443 2>/dev/null || true
    
    # Remove OUTPUT rules
    sudo iptables -t nat -D OUTPUT -p tcp --dport 30080 -d 127.0.0.1 -j DNAT --to-destination ${MINIKUBE_IP}:30080 2>/dev/null || true
    sudo iptables -t nat -D OUTPUT -p tcp --dport 30443 -d 127.0.0.1 -j DNAT --to-destination ${MINIKUBE_IP}:30443 2>/dev/null || true
    
    HOST_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
    if [ -n "$HOST_IP" ]; then
        sudo iptables -t nat -D OUTPUT -p tcp --dport 30080 -d $HOST_IP -j DNAT --to-destination ${MINIKUBE_IP}:30080 2>/dev/null || true
        sudo iptables -t nat -D OUTPUT -p tcp --dport 30443 -d $HOST_IP -j DNAT --to-destination ${MINIKUBE_IP}:30443 2>/dev/null || true
    fi
    echo "Iptables rules removed"
else
    echo "Minikube not running, skipping iptables cleanup"
fi

echo "=== Cleanup complete ==="
echo ""
echo "To completely remove Minikube, run: minikube delete"

