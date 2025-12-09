#!/bin/bash

set -e

echo "=== Connectivity Verification Script ==="
echo ""

# Get IPs
MINIKUBE_IP=$(minikube ip)
HOST_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to determine")

echo "IP Addresses:"
echo "  Minikube IP: $MINIKUBE_IP"
echo "  Host IP: $HOST_IP"
echo "  Public IP: $PUBLIC_IP"
echo ""

# Check Minikube status
echo "1. Minikube Status:"
minikube status | head -5
echo ""

# Check services
echo "2. Service Status:"
kubectl get svc nginx-proxy -n keycloak-proxy
echo ""

# Check pods
echo "3. Pod Status:"
kubectl get pods -n keycloak-proxy
echo ""

# Check IP forwarding
echo "4. IP Forwarding:"
IP_FORWARD=$(sudo sysctl -n net.ipv4.ip_forward)
echo "  net.ipv4.ip_forward = $IP_FORWARD"
if [ "$IP_FORWARD" != "1" ]; then
    echo "  WARNING: IP forwarding is not enabled!"
    echo "  Fix: sudo sysctl -w net.ipv4.ip_forward=1"
fi
echo ""

# Check iptables rules
echo "5. Iptables NAT Rules:"
echo "  PREROUTING rules for 30443:"
sudo iptables -t nat -L PREROUTING -n | grep 30443 || echo "    No PREROUTING rule found!"
echo ""
echo "  OUTPUT rules for 30443:"
OUTPUT_RULES=$(sudo iptables -t nat -L OUTPUT -n | grep 30443 || echo "")
if [ -z "$OUTPUT_RULES" ]; then
    echo "    No OUTPUT rules found!"
    echo "    Adding missing OUTPUT rules..."
    sudo iptables -t nat -A OUTPUT -p tcp --dport 30443 -d 127.0.0.1 -j DNAT --to-destination ${MINIKUBE_IP}:30443 2>/dev/null || true
    sudo iptables -t nat -A OUTPUT -p tcp --dport 30443 -d ${HOST_IP} -j DNAT --to-destination ${MINIKUBE_IP}:30443 2>/dev/null || true
    echo "    OUTPUT rules added"
else
    echo "$OUTPUT_RULES"
fi
echo ""

# Test connectivity
echo "6. Connectivity Tests:"
echo "  Testing from Minikube IP ($MINIKUBE_IP:30443):"
MINIKUBE_TEST=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 https://${MINIKUBE_IP}:30443 2>/dev/null || echo "FAILED")
if [ "$MINIKUBE_TEST" = "200" ] || [ "$MINIKUBE_TEST" = "302" ] || [ "$MINIKUBE_TEST" = "401" ]; then
    echo "    ✓ SUCCESS (HTTP $MINIKUBE_TEST)"
else
    echo "    ✗ FAILED (HTTP $MINIKUBE_TEST)"
fi

echo "  Testing from localhost (127.0.0.1:30443):"
LOCALHOST_TEST=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:30443 2>/dev/null || echo "FAILED")
if [ "$LOCALHOST_TEST" = "200" ] || [ "$LOCALHOST_TEST" = "302" ] || [ "$LOCALHOST_TEST" = "401" ]; then
    echo "    ✓ SUCCESS (HTTP $LOCALHOST_TEST)"
else
    echo "    ✗ FAILED (HTTP $LOCALHOST_TEST)"
fi

echo "  Testing from host IP (${HOST_IP}:30443):"
HOST_IP_TEST=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 https://${HOST_IP}:30443 2>/dev/null || echo "FAILED")
if [ "$HOST_IP_TEST" = "200" ] || [ "$HOST_IP_TEST" = "302" ] || [ "$HOST_IP_TEST" = "401" ]; then
    echo "    ✓ SUCCESS (HTTP $HOST_IP_TEST)"
else
    echo "    ✗ FAILED (HTTP $HOST_IP_TEST)"
fi

if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "Unable to determine" ]; then
    echo "  Testing from public IP (${PUBLIC_IP}:30443):"
    PUBLIC_IP_TEST=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 https://${PUBLIC_IP}:30443 2>/dev/null || echo "TIMEOUT")
    if [ "$PUBLIC_IP_TEST" = "200" ] || [ "$PUBLIC_IP_TEST" = "302" ] || [ "$PUBLIC_IP_TEST" = "401" ]; then
        echo "    ✓ SUCCESS (HTTP $PUBLIC_IP_TEST)"
    else
        echo "    ✗ FAILED/TIMEOUT (HTTP $PUBLIC_IP_TEST)"
        echo "    Note: This may be due to AWS Security Group blocking the port"
    fi
fi
echo ""

# Check firewall
echo "7. Firewall Status:"
UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1 || echo "UFW not installed")
echo "  $UFW_STATUS"
echo ""

# Summary
echo "=== Summary ==="
if [ "$MINIKUBE_TEST" != "FAILED" ] && [ "$LOCALHOST_TEST" != "FAILED" ]; then
    echo "✓ Internal connectivity is working"
    echo "✓ Service is accessible from Minikube network"
    if [ "$PUBLIC_IP_TEST" = "TIMEOUT" ] || [ -z "$PUBLIC_IP_TEST" ]; then
        echo "✗ External connectivity is blocked (likely AWS Security Group)"
        echo ""
        echo "To fix external access:"
        echo "1. Go to AWS EC2 Console → Security Groups"
        echo "2. Select your instance's security group"
        echo "3. Add Inbound Rule:"
        echo "   - Type: Custom TCP"
        echo "   - Port: 30443"
        echo "   - Source: 0.0.0.0/0 (or your specific IP)"
    fi
else
    echo "✗ Internal connectivity issues detected"
    echo "  Check the troubleshooting section in README.md"
fi

