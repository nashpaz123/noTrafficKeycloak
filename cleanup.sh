#!/bin/bash

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

echo "=== Cleanup complete ==="
echo ""
echo "To completely remove Minikube, run: minikube delete"

