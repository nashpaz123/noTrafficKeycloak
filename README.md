# Keycloak Deployment on Minikube

This project deploys a Keycloak server behind an Nginx reverse proxy with TLS (self-signed certificate) on a local Kubernetes cluster using Minikube. The reverse proxy is the only externally exposed component via NodePort.

## Architecture

- **Keycloak**: Running internally as a ClusterIP service (not exposed externally)
- **Nginx Reverse Proxy**: Running with TLS termination, exposed via NodePort
- **TLS**: Self-signed certificate for HTTPS
- **Kubernetes**: Minikube cluster with Docker driver

## Prerequisites

- Ubuntu 24.04 (or similar Linux distribution)
- Internet connection for downloading dependencies
- Sudo access for installing packages

## AWS Security Group Configuration

If deploying on an AWS EC2 instance, you need to open the following ports in your security group:

- **Port 22**: SSH (already open)
- **Port 80**: HTTP redirect (already open, but NodePort 30080 will be used)
- **Port 443**: HTTPS (already open, but NodePort 30443 will be used)
- **Port 30080**: HTTP NodePort (for testing HTTP redirect)
- **Port 30443**: HTTPS NodePort (primary access point)

**Note**: The NodePorts (30080 and 30443) are the actual ports that need to be accessible. Minikube tunnel (started automatically by setup.sh) makes these ports available on the host interface. If your security group only allows 80 and 443, you'll need to add rules for:
- Inbound TCP port 30080 from 0.0.0.0/0
- Inbound TCP port 30443 from 0.0.0.0/0

Alternatively, you can modify the NodePort values in `deploy.sh` to use ports 80 and 443, but this requires running Minikube with sudo privileges.

## Installation and Deployment

### Step 1: Setup Minikube Cluster

Run the setup script to install all dependencies and start Minikube:

```bash
chmod +x setup.sh
./setup.sh
```

This script will:
- Install Docker (if not already installed)
- Install kubectl (if not already installed)
- Install Minikube (if not already installed)
- Start a Minikube cluster with Docker driver
- Start Minikube tunnel to expose NodePort services on the host interface

**Note**: If Docker was just installed, you may need to log out and back in. The script will attempt to handle docker group permissions automatically. Minikube tunnel runs in the background to make NodePort services accessible from outside the Minikube VM.

### Step 2: Deploy Keycloak and Nginx

Deploy the Keycloak server and Nginx reverse proxy:

```bash
chmod +x deploy.sh
./deploy.sh
```

This script will:
- Create a Kubernetes namespace `keycloak-proxy`
- Generate self-signed TLS certificates
- Deploy Keycloak as an internal service (ClusterIP)
- Deploy Nginx reverse proxy with TLS termination
- Expose Nginx via NodePort (ports 30080 for HTTP, 30443 for HTTPS)

The deployment may take a few minutes for all pods to be ready.

### Step 3: Run Smoke Tests

Validate that the deployment completed successfully:

```bash
chmod +x smoke-test.sh
./smoke-test.sh
```

The smoke test script will:
- Verify all pods are running
- Check service configurations
- Test internal Keycloak connectivity
- Test HTTP to HTTPS redirect
- Test HTTPS endpoint accessibility
- Verify Keycloak login page is served

Upon successful completion, the script will display the access URL.

## Accessing Keycloak

### Local Access (Minikube)

After running the smoke test, you'll see the Minikube IP and ports. Access Keycloak at:

```
https://<MINIKUBE_IP>:30443
```

For example: `https://192.168.49.2:30443`

### Remote Access (AWS EC2)

If running on an AWS EC2 instance:

1. Get your EC2 public IP address
2. Access Keycloak at: `https://<EC2_PUBLIC_IP>:30443`
3. Make sure port 30443 is open in your security group

**Important**: You'll need to accept the self-signed certificate warning in your browser.

### Default Credentials

- **Username**: `admin`
- **Password**: `admin`

## Cleanup

To remove all deployed resources:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

This will:
- Delete the `keycloak-proxy` namespace and all resources
- Remove local certificate files

To completely remove Minikube:

```bash
minikube delete
```

## Troubleshooting

### Pods not starting

Check pod status:
```bash
kubectl get pods -n keycloak-proxy
kubectl describe pod <pod-name> -n keycloak-proxy
kubectl logs <pod-name> -n keycloak-proxy
```

### Cannot access from browser

1. Verify the NodePort service is running:
   ```bash
   kubectl get svc nginx-proxy -n keycloak-proxy
   ```

2. Check if the port is accessible:
   ```bash
   curl -k https://<IP>:30443
   ```

3. For AWS EC2, ensure the security group allows inbound traffic on port 30443

### Certificate issues

The self-signed certificate is generated automatically. If you need to regenerate it:
```bash
rm -rf certs
./deploy.sh
```

### Minikube not starting

If Minikube fails to start:
```bash
minikube delete
minikube start --driver=docker --verbose
```

## File Structure

```
.
├── README.md           # This file
├── setup.sh            # Setup script (installs dependencies, starts Minikube)
├── deploy.sh           # Deployment script (deploys Keycloak and Nginx)
├── smoke-test.sh       # Smoke test script (validates deployment)
├── cleanup.sh          # Cleanup script (removes all resources)
├── nginx.conf          # Nginx configuration file
└── .gitignore          # Git ignore file
```

## Notes

- Keycloak runs in development mode (`start-dev`) for simplicity
- The self-signed certificate is valid for 365 days
- All resources are deployed in the `keycloak-proxy` namespace
- Keycloak is only accessible through the Nginx reverse proxy (not directly exposed)
- HTTP traffic is automatically redirected to HTTPS
