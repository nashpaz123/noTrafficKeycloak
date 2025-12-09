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
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: keycloak-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:latest
        args:
        - start-dev
        - --http-relative-path=/
        env:
        - name: KEYCLOAK_ADMIN
          value: "admin"
        - name: KEYCLOAK_ADMIN_PASSWORD
          value: "admin"
        ports:
        - containerPort: 8080
          name: http
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: keycloak-proxy
spec:
  type: ClusterIP
  selector:
    app: keycloak
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
EOF

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
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-proxy
  namespace: keycloak-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-proxy
  template:
    metadata:
      labels:
        app: nginx-proxy
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 443
          name: https
        - containerPort: 80
          name: http
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: tls-cert
          mountPath: /etc/nginx/ssl
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
      - name: tls-cert
        secret:
          secretName: keycloak-tls
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-proxy
  namespace: keycloak-proxy
spec:
  type: NodePort
  selector:
    app: nginx-proxy
  ports:
  - port: 443
    targetPort: 443
    protocol: TCP
    name: https
    nodePort: 30443
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
    nodePort: 30080
EOF

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

