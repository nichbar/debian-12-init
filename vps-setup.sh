#!/bin/bash

# VPS Setup Script for Debian 12
# Automates initial VPS configuration: BBR, SSH port configuration, SSH key hardening, Xray core, Oh-My-Zsh, and UFW firewall

set -euo pipefail

# Ensure standard input is attached to a terminal if available (handles curl ... | bash)
if [ ! -t 0 ] && [ -c /dev/tty ]; then
    exec < /dev/tty 2>/dev/null || true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper logging functions
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

# Validate integer port between 1 and 65535
validate_port() {
    local port="$1"
    local name="$2"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Invalid $name: '$port'. Must be an integer between 1 and 65535."
        return 1
    fi
    return 0
}

# Prompt user for a port with a default value and validation
prompt_port() {
    local prompt_msg="$1"
    local default_val="$2"
    local var_name="$3"
    local desc="$4"
    local input_val=""

    while true; do
        read -r -p "$prompt_msg" input_val || true
        input_val="${input_val:-$default_val}"
        input_val="$(echo "$input_val" | tr -d '[:space:]')"
        if validate_port "$input_val" "$desc"; then
            printf -v "$var_name" '%s' "$input_val"
            break
        fi
    done
}

# Validate OpenSSH public key format
validate_ssh_public_key() {
    local key="$1"
    if [ -z "$key" ]; then
        return 1
    fi
    local tmpfile
    tmpfile="$(mktemp /tmp/ssh_pub_key.XXXXXX)"
    echo "$key" > "$tmpfile"
    local status=1
    if command -v ssh-keygen >/dev/null 2>&1; then
        if ssh-keygen -l -f "$tmpfile" >/dev/null 2>&1; then
            status=0
        fi
    else
        # Fallback regex check if ssh-keygen is unavailable
        if [[ "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-[^ ]+|sk-[^ ]+)[[:space:]]+[A-Za-z0-9+/=]+ ]]; then
            status=0
        fi
    fi
    rm -f "$tmpfile"
    return $status
}

# Safely set or update a directive in /etc/ssh/sshd_config
set_sshd_directive() {
    local key="$1"
    local value="$2"
    local file="/etc/ssh/sshd_config"
    if [ -f "$file" ]; then
        if grep -qE "^#?[[:space:]]*${key}[[:space:]]+" "$file"; then
            sed -i.bak -E "s|^#?[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$file" && rm -f "${file}.bak"
        else
            echo "${key} ${value}" >> "$file"
        fi
    fi
}

# Check if running as root
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Starting VPS setup for Debian 12..."
echo

# Step 1: Update system packages
print_status "Updating system package index..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
print_success "System package index updated"
echo

# Step 2: Install required packages
print_status "Installing required packages..."
apt-get install -y --no-install-recommends curl wget net-tools ufw zsh git procps nano openssh-client
print_success "Required packages installed"
echo

# Step 3: Enable BBR
print_status "Configuring BBR TCP congestion control..."
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-bbr.conf << 'EOF'
# BBR TCP Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

# Attempt to load tcp_bbr module if kernel supports it
modprobe tcp_bbr 2>/dev/null || true

if sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null 2>&1; then
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    if [[ "$current_cc" == *"bbr"* ]]; then
        print_success "BBR enabled successfully (current: $current_cc)"
    else
        print_warning "BBR configured, but current congestion control is $current_cc (may require reboot)"
    fi
else
    print_warning "Could not apply BBR sysctl settings (container/unsupported kernel). Continuing..."
fi
echo

# Step 4: Configure SSH & Public Key Hardening
prompt_port "Enter the new SSH port (default: 22): " "22" ssh_port "SSH port"

# Check for existing authorized keys
existing_keys_count=0
if [ -s /root/.ssh/authorized_keys ]; then
    existing_keys_count=$(grep -cE "^(ssh-|ecdsa-|sk-)" /root/.ssh/authorized_keys 2>/dev/null || echo "0")
fi

ssh_key_configured=false

echo
print_status "SSH Key Authentication Configuration:"
if [ "$existing_keys_count" -gt 0 ]; then
    print_status "Found $existing_keys_count existing SSH key(s) in /root/.ssh/authorized_keys."
fi

add_key_choice="n"
read -r -p "Do you want to add a public SSH key? (Will disable password login once set) [y/N]: " add_key_choice || true
add_key_choice="${add_key_choice:-n}"

if [[ "$add_key_choice" =~ ^[Yy]$ ]]; then
    while true; do
        echo
        print_status "Paste your SSH public key (e.g., ssh-ed25519 AAAAC3... user@example.com):"
        read -r pasted_key || true
        pasted_key="$(echo "$pasted_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        if [ -z "$pasted_key" ]; then
            print_warning "No key entered."
            skip_key="n"
            read -r -p "Skip adding SSH key and keep password login? [y/N]: " skip_key || true
            skip_key="${skip_key:-n}"
            if [[ "$skip_key" =~ ^[Yy]$ ]]; then
                break
            fi
            continue
        fi

        if validate_ssh_public_key "$pasted_key"; then
            mkdir -p /root/.ssh
            chmod 700 /root/.ssh
            touch /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys

            if ! grep -qxF "$pasted_key" /root/.ssh/authorized_keys 2>/dev/null; then
                echo "$pasted_key" >> /root/.ssh/authorized_keys
            fi

            ssh_key_configured=true
            print_success "Public SSH key added to /root/.ssh/authorized_keys"
            break
        else
            print_error "Invalid SSH public key format! Key must be a valid OpenSSH public key."
            retry_key="y"
            read -r -p "Would you like to try entering the key again? [Y/n]: " retry_key || true
            retry_key="${retry_key:-y}"
            if [[ ! "$retry_key" =~ ^[Yy]$ ]]; then
                print_warning "Skipped adding SSH key."
                break
            fi
        fi
    done
elif [ "$existing_keys_count" -gt 0 ]; then
    # User chose not to add a new key, but existing keys were detected
    disable_pwd_choice="n"
    read -r -p "Disable password authentication and rely on existing key(s)? [y/N]: " disable_pwd_choice || true
    disable_pwd_choice="${disable_pwd_choice:-n}"
    if [[ "$disable_pwd_choice" =~ ^[Yy]$ ]]; then
        ssh_key_configured=true
    fi
fi

if [ "$ssh_key_configured" = true ]; then
    permit_root="prohibit-password"
    password_auth="no"
    kbd_auth="no"
    print_status "Configuring SSH: Enforcing public key authentication and disabling password login..."
else
    permit_root="yes"
    password_auth="yes"
    kbd_auth="yes"
    print_warning "Password authentication will remain enabled."
fi

print_status "Configuring SSH on port $ssh_port..."

# 4a. Update /etc/ssh/sshd_config
set_sshd_directive "Port" "$ssh_port"
set_sshd_directive "PermitRootLogin" "$permit_root"
set_sshd_directive "PasswordAuthentication" "$password_auth"
set_sshd_directive "KbdInteractiveAuthentication" "$kbd_auth"
set_sshd_directive "PubkeyAuthentication" "yes"
if [ -f /etc/ssh/sshd_config ] && grep -qE "^#?[[:space:]]*ChallengeResponseAuthentication[[:space:]]+" /etc/ssh/sshd_config; then
    set_sshd_directive "ChallengeResponseAuthentication" "$kbd_auth"
fi

# 4b. Write drop-in configuration in /etc/ssh/sshd_config.d/ (first match wins in OpenSSH)
if [ -d /etc/ssh/sshd_config.d ]; then
    cat > /etc/ssh/sshd_config.d/01-vps-setup.conf << EOF
# Managed by vps-setup.sh
Port $ssh_port
PermitRootLogin $permit_root
PasswordAuthentication $password_auth
KbdInteractiveAuthentication $kbd_auth
PubkeyAuthentication yes
EOF
fi

# 4c. Debian 12 OpenSSH uses systemd socket activation (ssh.socket) by default.
# If ssh.socket is present, override ListenStream to actually change the listening port.
if systemctl list-unit-files ssh.socket >/dev/null 2>&1; then
    print_status "Configuring systemd ssh.socket drop-in for port $ssh_port..."
    mkdir -p /etc/systemd/system/ssh.socket.d
    cat > /etc/systemd/system/ssh.socket.d/listen.conf << EOF
[Socket]
ListenStream=
ListenStream=$ssh_port
EOF
    systemctl daemon-reload
    if systemctl is-active --quiet ssh.socket; then
        systemctl restart ssh.socket
        print_success "ssh.socket restarted on port $ssh_port"
    fi
fi

# Also reload ssh service if running as standard service
if systemctl is-active --quiet ssh.service || systemctl is-active --quiet ssh; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    print_success "SSH service restarted on port $ssh_port"
fi

# Verify SSH daemon configuration
if command -v sshd >/dev/null 2>&1; then
    if sshd -t; then
        print_success "SSH configuration verified with sshd -t"
    else
        print_error "SSH configuration test failed! Please verify /etc/ssh/sshd_config"
        exit 1
    fi
fi

if [ "$ssh_key_configured" = true ]; then
    print_success "SSH key authentication is now active (PasswordAuthentication no, PermitRootLogin prohibit-password)."
else
    print_warning "Note: Root login with password remains enabled (PermitRootLogin yes). For enhanced security, configure an SSH key."
fi
echo

# Step 5: Prompt for Xray configuration and install
while true; do
    prompt_port "Enter the port for Xray core (default: 443): " "443" xray_port "Xray port"
    if [ "$xray_port" -eq "$ssh_port" ]; then
        print_error "Xray port ($xray_port) cannot be the same as SSH port ($ssh_port). Please choose another port."
    else
        break
    fi
done

print_status "Installing Xray core..."
if bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root; then
    print_success "Xray core installed"
else
    print_error "Failed to install Xray core. Please check network connection and retry."
    exit 1
fi
echo

# Step 6: Interactive Xray configuration
mkdir -p /usr/local/etc/xray
config_file="/usr/local/etc/xray/config.json"

# Provide starter configuration template if file doesn't exist or is empty
if [ ! -s "$config_file" ]; then
    client_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
    if [ -z "$client_uuid" ]; then
        client_uuid="00000000-0000-0000-0000-000000000000"
    fi
    cat > "$config_file" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $xray_port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$client_uuid",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
fi

print_status "Opening nano editor for Xray configuration ($config_file)..."
echo
print_warning "Review or paste your complete Xray configuration into nano."
print_warning "Ensure your inbound configuration listens on port $xray_port."
print_warning "Save and exit nano: press Ctrl+O, Enter, then Ctrl+X."
echo
read -r -p "Press Enter to open editor..." _dummy || true

editor_bin="${EDITOR:-nano}"
if ! command -v "$editor_bin" >/dev/null 2>&1; then
    editor_bin="nano"
fi

while true; do
    if [ -c /dev/tty ]; then
        "$editor_bin" "$config_file" < /dev/tty > /dev/tty
    else
        "$editor_bin" "$config_file"
    fi

    print_status "Validating Xray configuration..."
    if command -v xray >/dev/null 2>&1; then
        if xray run -test -c "$config_file"; then
            print_success "Xray configuration is valid"
            break
        else
            print_error "Xray configuration validation failed!"
            fix_choice="y"
            read -r -p "Would you like to reopen nano to correct the configuration? [Y/n]: " fix_choice || true
            fix_choice="${fix_choice:-y}"
            if [[ ! "$fix_choice" =~ ^[Yy]$ ]]; then
                print_warning "Continuing setup. Note: Xray service might fail to start until configuration is fixed."
                break
            fi
        fi
    else
        print_warning "xray binary not found in PATH; skipping validation test."
        break
    fi
done
echo

# Step 7: Enable and start Xray service
print_status "Starting Xray service..."
systemctl enable xray || true
if systemctl restart xray; then
    print_success "Xray service enabled and started"
else
    print_warning "Xray service failed to start. You can check logs later using: journalctl -u xray -e"
fi
echo

# Step 8: Install Oh-My-Zsh and configure default shell
print_status "Installing Oh-My-Zsh..."
if [ -d "/root/.oh-my-zsh" ]; then
    print_warning "Oh-My-Zsh is already installed at /root/.oh-my-zsh. Skipping download."
else
    if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
        print_success "Oh-My-Zsh installed"
    else
        print_warning "Oh-My-Zsh installation script returned a non-zero exit status. Continuing..."
    fi
fi

# Set default shell to zsh for root
if command -v zsh >/dev/null 2>&1; then
    zsh_path="$(command -v zsh)"
    current_shell="$(getent passwd root 2>/dev/null | cut -d: -f7 || echo "$SHELL")"
    if [ "$current_shell" != "$zsh_path" ]; then
        chsh -s "$zsh_path" root 2>/dev/null || true
        print_success "Default shell set to $zsh_path for root"
    else
        print_status "Root default shell is already $zsh_path"
    fi
fi
echo

# Step 9: Configure UFW Firewall
print_status "Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$ssh_port/tcp" comment "SSH"
ufw allow "$xray_port/tcp" comment "Xray TCP"
ufw allow "$xray_port/udp" comment "Xray UDP"
ufw --force enable
print_success "UFW enabled with rules for SSH ($ssh_port/tcp) and Xray ($xray_port/tcp, $xray_port/udp)"
echo

print_success "========================================="
print_success "VPS Setup Complete!"
print_success "========================================="
print_status "Summary:"
echo "  - BBR TCP congestion control configured"
echo "  - SSH configured on port: $ssh_port"
if [ "$ssh_key_configured" = true ]; then
    echo "  - SSH authentication: Public key only (password authentication disabled)"
else
    echo "  - SSH authentication: Password authentication enabled (key not configured)"
fi
echo "  - Xray core configured on port: $xray_port"
echo "  - UFW firewall enabled (allowed: $ssh_port/tcp, $xray_port/tcp, $xray_port/udp)"
echo "  - Oh-My-Zsh installed (root shell: zsh)"
echo
if [ "$ssh_key_configured" = true ]; then
    print_warning "CRITICAL: Before disconnecting, verify SSH login with your private key in a NEW terminal:"
    echo "  ssh -i <path-to-private-key> -p $ssh_port root@<your-server-ip>"
else
    print_warning "CRITICAL: Before disconnecting, verify SSH in a NEW terminal window:"
    echo "  ssh -p $ssh_port root@<your-server-ip>"
fi
echo

reboot_answer="n"
read -r -p "Would you like to reboot the server now? [y/N]: " reboot_answer || true
reboot_answer="${reboot_answer:-n}"
if [[ "$reboot_answer" =~ ^[Yy]$ ]]; then
    print_status "Rebooting in 5 seconds... (Press Ctrl+C to cancel)"
    sleep 5
    print_status "Rebooting now..."
    reboot
else
    print_status "Reboot skipped. You can manually reboot when ready with: reboot"
fi
