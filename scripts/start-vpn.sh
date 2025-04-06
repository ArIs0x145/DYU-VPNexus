#!/bin/sh
set -e

# Color and log format settings
# -----------------------------
LOG_INFO="[INFO]"
LOG_WARN="[WARN]"
LOG_ERROR="[ERROR]"

# Log functions
log_info() { echo "${LOG_INFO} $1"; }
log_warn() { echo "${LOG_WARN} $1"; }
log_error() { echo "${LOG_ERROR} $1" >&2; }

# Error handling function, display error message and exit
handle_error() {
    log_error "$1"
    # Show VPN logs if available
    if [ -f /var/log/vpn/openfortivpn.log ]; then
        log_info "VPN log contents:"
        cat /var/log/vpn/openfortivpn.log
    fi
    exit 1
}

# Cleanup function for signal handling
cleanup() {
    log_info "Shutting down VPN connection..."
    # Kill active VPN processes
    if [ -n "$VPN_PID" ]; then
        kill -TERM "$VPN_PID" 2>/dev/null || true
    fi
    # Kill all openfortivpn processes
    pkill -TERM openfortivpn 2>/dev/null || true
    exit 0
}

# Create configuration directory
mkdir -p /etc/openfortivpn

# Generate configuration file
log_info "Generating VPN configuration file..."
cat > /etc/openfortivpn/config << EOL
host = ${VPN_HOST}
port = ${VPN_PORT}
username = ${VPN_USERNAME}
password = ${VPN_PASSWORD}
set-dns = ${SET_DNS:-1}
use-peerdns = ${USE_PEERDNS:-1}
pppd-use-peerdns = ${USE_PEERDNS:-1}
persistent = 1
EOL

# Add trusted certificate (if provided)
if [ -n "$TRUSTED_CERT" ]; then
    echo "trusted-cert = ${TRUSTED_CERT}" >> /etc/openfortivpn/config
fi

log_info "VPN configuration file generated successfully"

# Start VPN connection
log_info "Connecting to VPN ${VPN_HOST}:${VPN_PORT}..."

# Enable IP forwarding (for routing/NAT functionality)
if ! sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1; then
    log_warn "Failed to enable IP forwarding, some functionality may be limited"
else
    log_info "IP forwarding enabled"
fi

# Ensure /var/log/vpn directory exists
mkdir -p /var/log/vpn

# Save VPN server IP for later use
VPN_SERVER_IP=$(getent hosts "$VPN_HOST" | awk '{print $1}' | head -n 1)
if [ -n "$VPN_SERVER_IP" ]; then
    log_info "VPN server IP: ${VPN_SERVER_IP}"
    # Save to temp file for reconnection
    echo "$VPN_SERVER_IP" > /tmp/vpn_server_ip
fi

# Save original network configuration
DEFAULT_IF=$(ip route | grep default | awk '{print $5}')
DEFAULT_GW=$(ip route | grep default | awk '{print $3}')
if [ -n "$DEFAULT_IF" ] && [ -n "$DEFAULT_GW" ]; then
    # Save original default route information to temp file
    echo "$DEFAULT_IF $DEFAULT_GW" > /tmp/original_route
    log_info "Saved original route: via $DEFAULT_GW dev $DEFAULT_IF"
fi

# Ensure route to VPN server uses physical network
if [ -n "$VPN_SERVER_IP" ] && [ -n "$DEFAULT_IF" ] && [ -n "$DEFAULT_GW" ]; then
    # Delete existing route to avoid conflicts
    ip route del "$VPN_SERVER_IP" via "$DEFAULT_GW" 2>/dev/null || true
    
    # Add new route with retries to ensure success
    RETRY=0
    MAX_RETRY=3
    ROUTE_ADDED=false
    
    while [ $RETRY -lt $MAX_RETRY ] && [ "$ROUTE_ADDED" = "false" ]; do
        if ip route add "$VPN_SERVER_IP" via "$DEFAULT_GW" dev "$DEFAULT_IF" 2>/dev/null; then
            log_info "Successfully added VPN server route: $VPN_SERVER_IP via $DEFAULT_GW"
            ROUTE_ADDED=true
        else
            RETRY=$((RETRY + 1))
            log_warn "Adding VPN server route attempt $RETRY/$MAX_RETRY failed, retrying..."
            sleep 1
        fi
    done
    
    if [ "$ROUTE_ADDED" = "false" ]; then
        log_warn "Failed to add VPN server route, trying alternative method"
        # Try alternative method - static host route
        if ! ip route add "$VPN_SERVER_IP" dev "$DEFAULT_IF" 2>/dev/null; then
            log_warn "Adding static host route also failed, VPN reconnection may be unstable"
        else
            log_info "Successfully added VPN server static host route"
        fi
    fi
fi

# Start openfortivpn in background
openfortivpn -c /etc/openfortivpn/config -o /var/log/vpn/openfortivpn.log &
VPN_PID=$!

# Register signal handlers
trap cleanup INT TERM QUIT

# Check if VPN process exists
if ! kill -0 $VPN_PID 2>/dev/null; then
    handle_error "VPN process failed to start"
fi

log_info "VPN process started, PID: $VPN_PID"

# Wait for ppp0 interface to appear
TIMEOUT=30
COUNTER=0

log_info "Waiting for VPN connection to establish..."
while [ $COUNTER -lt $TIMEOUT ]; do
    if ip addr show ppp0 > /dev/null 2>&1; then
        # Get assigned VPN IP address - BusyBox compatible
        VPN_IP=$(ip -4 addr show ppp0 | grep inet | awk '{print $2}' | cut -d'/' -f1)
        if [ -n "$VPN_IP" ]; then
            log_info "ppp0 interface up"
            break
        fi
    fi
    
    # Check if VPN process still exists
    if ! kill -0 $VPN_PID 2>/dev/null; then
        handle_error "VPN process terminated, cannot establish connection"
    fi
    
    COUNTER=$((COUNTER + 1))
    sleep 1
done

if [ $COUNTER -ge $TIMEOUT ]; then
    handle_error "Timed out waiting for VPN connection"
fi

log_info "VPN IP address: $VPN_IP"

# Set up routing (ensure traffic goes through VPN)
log_info "Setting up routing table..."

# Set default route through VPN
if ! ip route change default dev ppp0 2>/dev/null; then
    log_warn "Failed to update default route, trying to add new route"
    ip route add default dev ppp0 2>/dev/null || log_warn "Failed to set default route through VPN"
fi

# Display current routing table
log_info "Current routing table:"
ip route | grep -v '^169.254' | sort

# Main loop: monitor VPN connection and keep container running
log_info "VPN connection established, starting monitoring..."
log_info "Log file location: /var/log/vpn/openfortivpn.log"

# Initialize VPN status
FIRST_RUN=true
echo "[$(date)] VPN 服務啟動，IP: $VPN_IP" > /var/log/vpn/vpn-status.log

# Main loop: check VPN status
while true; do
    # Check ppp0 interface
    if ! ip addr show ppp0 > /dev/null 2>&1; then
        log_warn "ppp0 interface lost, VPN may be disconnected"
        echo "[$(date)] ppp0 接口丟失" >> /var/log/vpn/vpn-status.log
        break
    else
        # Periodically record VPN status
        echo "[$(date)] VPN 連接正常" >> /var/log/vpn/vpn-status.log
    fi
    
    # Check if VPN process exists
    if ! kill -0 $VPN_PID 2>/dev/null; then
        log_error "VPN process terminated"
        echo "[$(date)] VPN 進程終止" >> /var/log/vpn/vpn-status.log
        break
    fi
    
    sleep 60
done

log_info "Starting DYU-VPNexus VPN client..."

# If VPN connection is lost, restart VPN process
cleanup

# Execute same script to restart VPN
exec "$0" "$@"

log_info "VPN connection successfully established!" 