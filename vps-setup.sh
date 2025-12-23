#!/bin/bash

# VPS Setup Script for Debian 12
# This script automates the initial VPS setup including SSH hardening and Xray core installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Starting VPS setup for Debian 12..."
echo

# Step 1: Update system
print_status "Updating system packages..."
apt update
print_success "System updated"
echo

# Step 2: Install required packages
print_status "Installing required packages..."
apt install -y curl wget net-tools ufw zsh git
print_success "Required packages installed"
echo

# Step 3: Enable BBR
print_status "Enabling BBR TCP congestion control..."
cat >> /etc/sysctl.conf << 'EOF'

# BBR TCP Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p
print_success "BBR enabled"
echo

# Step 4: Prompt for SSH configuration
read -p "Enter the new SSH port (default: 22): " ssh_port
ssh_port=${ssh_port:-22}

print_status "Configuring SSH on port $ssh_port..."
sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config || echo "Port $ssh_port" >> /etc/ssh/sshd_config
sed -i "s/#PermitRootLogin yes/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
print_success "SSH configured for port $ssh_port"
echo

# Step 5: Prompt for Xray configuration
read -p "Enter the port for Xray core (default: 443): " xray_port
xray_port=${xray_port:-443}

print_status "Installing Xray core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --version 25.3.6
print_success "Xray core installed"
echo

# Step 6: Interactive Xray configuration
print_status "Opening nano editor for Xray configuration..."
echo
print_warning "Please paste your complete Xray configuration into nano."
print_warning "Save the file by pressing Ctrl+X, then Y, then Enter."
echo
mkdir -p /usr/local/etc/xray
nano /usr/local/etc/xray/config.json
print_success "Xray configuration saved"
echo

# Step 7: Enable and start Xray service
print_status "Starting Xray service with new configuration..."
systemctl enable xray
systemctl restart xray
print_success "Xray service enabled and started"
echo

# Step 8: Install Oh-My-Zsh
print_status "Installing Oh-My-Zsh..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
print_success "Oh-My-Zsh installed"
echo

# Step 9: Configure UFW
print_status "Configuring UFW firewall..."
ufw --force reset
ufw allow $ssh_port/tcp
ufw allow $xray_port/tcp
ufw allow $xray_port/udp
ufw --force enable
print_success "UFW enabled with rules for SSH ($ssh_port/tcp) and Xray ($xray_port/tcp, $xray_port/udp)"
echo

print_success "========================================="
print_success "VPS Setup Complete!"
print_success "========================================="
print_status "Summary:"
echo "  - BBR enabled for better network performance"
echo "  - SSH configured on port: $ssh_port"
echo "  - Xray core configured on port: $xray_port"
echo "  - Firewall (UFW) enabled with required rules"
echo "  - Oh-My-Zsh installed"
echo
print_warning "IMPORTANT: Remember to:"
echo "  1. Configure your Xray clients with port $xray_port"
echo "  2. Update your SSH client to use port $ssh_port"
echo "  3. The server will reboot in 10 seconds. Press Ctrl+C to cancel."
echo
sleep 10
print_status "Rebooting now..."
reboot
