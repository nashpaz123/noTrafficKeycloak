#!/bin/bash  -x

set -e

echo "=== Setting up Minikube cluster ==="

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo "Please do not run as root"
   exit 1
fi

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    echo "Docker installed. Group membership updated."
    echo "Note: If docker commands fail, you may need to log out and back in, or use: newgrp docker"
else
    echo "Docker is already installed"
fi

# Install kubectl if not already installed
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    echo "kubectl installed"
else
    echo "kubectl is already installed"
fi

# Install Minikube if not already installed
if ! command -v minikube &> /dev/null; then
    echo "Installing Minikube..."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
    echo "Minikube installed"
else
    echo "Minikube is already installed"
fi

# Start Minikube cluster with docker driver
echo "Starting Minikube cluster..."
if minikube status &> /dev/null; then
    echo "Minikube cluster already exists, deleting old cluster..."
    minikube delete
fi

# Start minikube with docker driver
echo "Starting Minikube (this may take a few minutes)..."
if ! minikube start --driver=docker; then
    echo "Warning: Minikube start failed. This might be due to docker permissions."
    echo "If you see permission errors, try: newgrp docker"
    echo "Then run: minikube start --driver=docker"
    exit 1
fi

# Enable ingress addon (optional, but useful)
# minikube addons enable ingress

echo "=== Minikube cluster is ready ==="
minikube status

# Port forwarding will be set up automatically by deploy.sh after services are created
echo ""
echo "Note: Port forwarding for NodePorts will be configured during deployment."

