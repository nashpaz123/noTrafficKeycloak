# Keycloak Deployment on Minikube

Thi s project deploys a Keycloak server behind Nginx reverse proxy with TLS (self-signed certificate) on a local Kubernetes cluster using Minikube. The reverse proxy is the only externally exposed component exposed via NodePort

## Architecture

- **Keycloak**: Running internally as a ClusterIP service 
- **Nginx Reverse Proxy**: Running with TLS termination, exposed via NodePort
- **TLS**: Self-signed certificate for HTTPS
- **Kubernetes**: Minikube cluster with Docker driver

## Prerequisites

- tested on Ubuntu 24.04 aws instance with all ports open (see below for proper sg rules)

## AWS Security group conf

deploying on an AWS EC2 instance, you need to open the ports in your security group:

- **Port 22**: SSH (already open)
- **Port 80**: HTTP redirect (  NodePort 30080 will be used)
- **Port 443**: HTTPS (  NodePort 30443 will be used)
- **Port 30080**: HTTP NodePort (for testing HTTP redirect - 301 moved)
- **Port 30443**: HTTPS NodePort (primary client facing point)

**Note**: The NodePorts (30080 and 30443) are the actual ports that need to be accessible. Iptables port forwarding (configured automatically by deploy.sh) makes these ports available on the host interface. If your security group only allows 80 and 443, add rules for:
- Inbound TCP port 30080 from 0.0.0.0/0
- Inbound TCP port 30443 from 0.0.0.0/0

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

**Note**: If Docker was just installed, you may need to log out and back in. The script will attempt to handle docker group permissions automatically. Port forwarding for NodePorts will be configured automatically during deployment.

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
- Configure iptables port forwarding to make NodePorts accessible on host interface

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

### Step 4: Verify Connectivity (if running into munikube tunneling issues)

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

After running the smoke test, you'll see the Minikube IP and ports. Access Keycloak on the local machine at:

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

1. **Verify NodePort service is running:**
   ```bash
   kubectl get svc nginx-proxy -n keycloak-proxy
   # Should show e.g:
#   ubuntu@ip-172-31-46-210:~$ kubectl get svc nginx-proxy -n keycloak-proxy
#NAME          TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
#nginx-proxy   NodePort   10.101.90.141   <none>        443:30443/TCP,80:30080/TCP   71m
   ```

2. **Check IP forwarding is enabled:**
   ```bash
   sudo sysctl net.ipv4.ip_forward
   # If not 1, enable it:
   sudo sysctl -w net.ipv4.ip_forward=1
   sudo sh -c 'echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf'
   ```

3. **Verify iptables NAT rules exist:**
   ```bash
   MINIKUBE_IP=$(minikube ip)
   sudo iptables -t nat -L PREROUTING -n | grep 30443
   sudo iptables -t nat -L OUTPUT -n | grep 30443
   ```
   
   If rules are missing, run the deploy script again or manually add them:
   ```bash
   MINIKUBE_IP=$(minikube ip)
   HOST_IP=$(hostname -I | awk '{print $1}')
   
   # PREROUTING rule (for external traffic)
   sudo iptables -t nat -A PREROUTING -p tcp --dport 30443 -j DNAT --to-destination ${MINIKUBE_IP}:30443
   
   # OUTPUT rules (for localhost and host IP)
   sudo iptables -t nat -A OUTPUT -p tcp --dport 30443 -d 127.0.0.1 -j DNAT --to-destination ${MINIKUBE_IP}:30443
   sudo iptables -t nat -A OUTPUT -p tcp --dport 30443 -d ${HOST_IP} -j DNAT --to-destination ${MINIKUBE_IP}:30443
   ```

4. **Test from the server itself:**
   ```bash
   # Should work
   curl -k https://localhost:30443
   curl -k https://$(minikube ip):30443
   ```

5. **Verify AWS Security Group:**
   - Ensure port 30443 (or your NodePort) is open in the security group
   - Check that the rule allows traffic from your IP or 0.0.0.0/0
   - Verify the security group is attached to your EC2 instance

6. **Check for other firewalls:**
   ```bash
   sudo ufw status
   sudo iptables -L INPUT -n
   ```

### NodePort Configuration

The NodePorts are **statically configured** in the service definition:
- **HTTPS**: Port 30443 (NodePort)
- **HTTP**: Port 30080 (NodePort)

These are explicitly set in `deploy.sh`. Iptables port forwarding rules are automatically configured to make these NodePorts accessible on the host interface. To verify the NodePorts are correctly assigned:
```bash
kubectl get svc nginx-proxy -n keycloak-proxy -o yaml | grep nodePort
```

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
├── README.md                    # This file
├── setup.sh                     # Setup script (installs dependencies, starts Minikube)
├── deploy.sh                    # Deployment script (deploys Keycloak and Nginx)
├── smoke-test.sh                # Smoke test script (validates deployment)
├── cleanup.sh                   # Cleanup script (removes all resources)
├── verify-connectivity.sh      # Optional connectivity verification script
├── nginx.conf                   # Nginx configuration file
├── .gitignore                   # Git ignore file
└── k8s/                         # Kubernetes manifest files
    ├── keycloak-deployment.yaml # Keycloak deployment
    ├── keycloak-service.yaml    # Keycloak service (ClusterIP)
    ├── nginx-deployment.yaml    # Nginx reverse proxy deployment
    └── nginx-service.yaml       # Nginx service (NodePort)
```

## Notes

- Keycloak runs in development mode (`start-dev`) for simplicity
- The self-signed certificate is valid for 365 days
- All resources are deployed in the `keycloak-proxy` namespace
- Keycloak is only accessible through the Nginx reverse proxy (not directly exposed)
- HTTP traffic is automatically redirected to HTTPS
