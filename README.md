# Keycloak Deployment on Minikube

This project deploys a Keycloak server behind an Nginx reverse proxy with TLS (self-signed certificate) on a local Kubernetes cluster using Minikube. The reverse proxy is the only externally exposed component via NodePort.

## Architecture

- **Keycloak**: Running internally as a ClusterIP service (not exposed externally)
- **Nginx Reverse Proxy**: Running with TLS termination, exposed via LoadBalancer (using minikube tunnel)
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
- **Port 80**: HTTP (redirects to HTTPS)
- **Port 443**: HTTPS (primary access point)

**Note**: The service uses LoadBalancer type with minikube tunnel, which makes it accessible on localhost ports 80 and 443. For AWS EC2 access, ensure your security group allows:
- Inbound TCP port 80 from 0.0.0.0/0
- Inbound TCP port 443 from 0.0.0.0/0

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

**Note**: If Docker was just installed, you may need to log out and back in. The script will attempt to handle docker group permissions automatically. Minikube tunnel will be started automatically during deployment to expose the LoadBalancer service.

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
- Expose Nginx via LoadBalancer (accessible on ports 80 and 443 via minikube tunnel)

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

### Step 4: Verify Connectivity (Optional)

If you're experiencing connection issues, run the connectivity verification script:

```bash
chmod +x verify-connectivity.sh
./verify-connectivity.sh
```

This script will:
- Check all system configurations
- Verify iptables rules
- Test connectivity from multiple IP addresses
- Identify missing configurations
- Provide specific fix instructions

## Accessing Keycloak

### Local Access (Minikube)

After running the smoke test, you'll see the LoadBalancer external IP. Access Keycloak at:

```
https://localhost:443
```

Or if LoadBalancer has an external IP:
```
https://<EXTERNAL_IP>:443
```

### Remote Access (AWS EC2)

If running on an AWS EC2 instance:

1. Ensure minikube tunnel is running (started automatically by deploy.sh)
2. Access Keycloak at: `https://<EC2_PUBLIC_IP>:443` or `https://localhost:443`
3. Make sure ports 80 and 443 are open in your security group

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

### Comprehensive Connectivity Tests

Run these tests to diagnose connection issues:

```bash
# 1. Check Minikube status
minikube status

# 2. Check service and pod status
kubectl get svc -n keycloak-proxy
kubectl get pods -n keycloak-proxy

# 3. Check IP forwarding
sudo sysctl net.ipv4.ip_forward
# Should output: net.ipv4.ip_forward = 1

# 4. Check iptables NAT rules
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"
sudo iptables -t nat -L PREROUTING -n | grep 30443
sudo iptables -t nat -L OUTPUT -n | grep 30443

# 5. Test connectivity from Minikube IP
curl -k -v https://$MINIKUBE_IP:30443

# 6. Test connectivity from localhost
curl -k -v https://localhost:30443

# 7. Test connectivity from public IP (replace with your EC2 IP)
curl -k -v https://<EC2_PUBLIC_IP>:30443

# 8. Check if port is listening (should show nothing for NodePort)
sudo ss -tlnp | grep 30443

# 9. Verify firewall status
sudo ufw status
sudo iptables -L INPUT -n
```

### Pods not starting

Check pod status:
```bash
kubectl get pods -n keycloak-proxy
kubectl describe pod <pod-name> -n keycloak-proxy
kubectl logs <pod-name> -n keycloak-proxy
```

### Cannot access from browser (Connection Timeout)

If you get "ERR_CONNECTION_TIMED_OUT" or "ERR_CONNECTION_REFUSED":

1. **Verify LoadBalancer service is running:**
   ```bash
   kubectl get svc nginx-proxy -n keycloak-proxy
   # Should show LoadBalancer type
   ```

2. **Check if minikube tunnel is running:**
   ```bash
   pgrep -f "minikube tunnel"
   # Should show a process ID
   ```
   
   If not running, start it:
   ```bash
   minikube tunnel
   # Run in background: nohup minikube tunnel > /tmp/minikube-tunnel.log 2>&1 &
   ```

3. **Check LoadBalancer external IP:**
   ```bash
   kubectl get svc nginx-proxy -n keycloak-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   # Should show an IP address (usually 127.0.0.1 or 10.x.x.x with minikube tunnel)
   ```

4. **Test from the server itself:**
   ```bash
   # Should work
   curl -k https://localhost:443
   curl -k http://localhost:80
   ```

5. **Verify AWS Security Group:**
   - Ensure ports 80 and 443 are open in the security group
   - Check that the rule allows traffic from your IP or 0.0.0.0/0
   - Verify the security group is attached to your EC2 instance

6. **Check for other firewalls:**
   ```bash
   sudo ufw status
   sudo iptables -L INPUT -n
   ```

### LoadBalancer Configuration

The service uses **LoadBalancer** type, which with minikube tunnel makes it accessible on standard ports:
- **HTTPS**: Port 443
- **HTTP**: Port 80

The minikube tunnel creates a route that makes the LoadBalancer service accessible on localhost. This is the recommended approach for external access with Minikube.

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

### Iptables rules not persisting

Iptables rules are not persistent across reboots. To make them persistent:
```bash
# Install iptables-persistent
sudo apt-get install -y iptables-persistent

# Save current rules
sudo netfilter-persistent save
```

Or add the rules to a startup script that runs on boot.

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
