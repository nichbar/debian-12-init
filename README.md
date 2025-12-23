# VPS Setup Script for Debian 12

An interactive bash script that automates the complete setup of a new Debian 12 VPS with security hardening, network optimization, and Xray core installation.

## Quick Install (One-Liner)

**Easiest way to run:**

```bash
curl -sSL https://raw.githubusercontent.com/nichbar/debian-12-init/main/vps-setup.sh | bash
```

## GitHub Deployment

To deploy this script on GitHub:

1. **Create a new repository** on GitHub
2. **Upload the files**:
   - `vps-setup.sh` - Main script
   - `README.md` - This documentation
3. **Update the URLs** in this README with your actual repository path

**Repository Structure:**
```
your-repo/
├── main/
│   ├── vps-setup.sh      # Main setup script
│   └── README.md         # Documentation
```

Your one-liner will then be:
```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/vps-setup.sh | bash
```

## Features

- 🚀 **System Updates**: Automatically updates package repositories and installs essential tools
- 🔧 **BBR TCP Optimization**: Enables BBR congestion control for better network performance
- 🔒 **SSH Hardening**: Interactive SSH port configuration with firewall rules
- 🌐 **Xray Core**: Installs and configures Xray with custom user-provided configuration
- 🔥 **UFW Firewall**: Configures firewall with proper TCP/UDP rules
- ⚡ **Oh-My-Zsh**: Installs Oh-My-Zsh for improved terminal experience

## Requirements

- **Operating System**: Debian 12
- **Privileges**: Root access required
- **Network**: Internet connection for downloading packages

## Script Workflow

The script will guide you through the following steps:

### 1. System Preparation
- Updates package repositories
- Installs essential packages: `curl`, `wget`, `net-tools`, `ufw`, `zsh`, `git`

### 2. Network Optimization
- Enables BBR TCP congestion control for improved network performance
- Applies system-level network settings

### 3. SSH Configuration
- **Interactive**: Prompts for custom SSH port (default: 22)
- Updates SSH daemon configuration
- Configures firewall rules for the selected port

### 4. Xray Core Installation
- Installs Xray core version 25.3.6
- **Interactive**: Opens nano editor for custom Xray configuration
- You can paste your complete `config.json` file here
- Supports any Xray protocol (VMess, VLESS, Trojan, etc.)

### 5. Service Activation
- Enables Xray service for automatic startup
- **Starts Xray immediately** to verify configuration works
- Script will fail if config is invalid (good error handling)

### 6. Terminal Enhancement
- Installs Oh-My-Zsh with default settings
- Sets up improved terminal environment

### 7. Firewall Configuration
- Configures UFW with rules for:
  - SSH port (TCP)
  - Xray port (TCP + UDP)
- Enables firewall automatically

### 8. System Reboot
- Automatic reboot to apply all changes
- Countdown timer allows cancellation

## Xray Configuration

When the script prompts for Xray configuration, you'll see this interface:

```
Opening nano editor for Xray configuration...

WARNING: Please paste your complete Xray configuration into nano.
WARNING: Save the file by pressing Ctrl+X, then Y, then Enter.

[ nano editor opens with /usr/local/etc/xray/config.json ]
```

### Example Xray Configurations

#### VMess Configuration:
```json
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "your-uuid-here",
            "alterId": 0
          }
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
```

#### VLESS Configuration:
```json
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "your-uuid-here",
            "encryption": "none"
          }
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
```

## Post-Setup

After the script completes and the system reboots:

1. **SSH Access**: Connect using your configured port:
   ```bash
   ssh root@your-server-ip -p YOUR_SSH_PORT
   ```

2. **Xray Service**: Check status:
   ```bash
   systemctl status xray
   ```

3. **Firewall Status**: View UFW rules:
   ```bash
   ufw status verbose
   ```

4. **BBR Verification**: Verify BBR is enabled:
   ```bash
   sysctl net.ipv4.tcp_congestion_control
   ```

## File Locations

- **Xray Config**: `/usr/local/etc/xray/config.json`
- **SSH Config**: `/etc/ssh/sshd_config`
- **UFW Config**: `/etc/ufw/user.rules`
- **System Config**: `/etc/sysctl.conf`

## Security Notes

- ⚠️ **Important**: Remember your SSH port and update SSH client accordingly
- 🔐 **Firewall**: All ports are blocked except SSH and Xray ports you configure
- 🛡️ **Root Access**: SSH root login is enabled for convenience - consider disabling later

## Troubleshooting

### Common Issues

1. **Script Permission Denied**:
   ```bash
   chmod +x vps-setup.sh
   ```

2. **SSH Connection Refused**:
   - Check firewall rules: `ufw status`
   - Verify SSH config: `cat /etc/ssh/sshd_config | grep Port`

3. **Xray Service Not Starting**:
   - Check logs: `journalctl -u xray -f`
   - Validate config: `xray -config /usr/local/etc/xray/config.json -test`

4. **BBR Not Enabled**:
   - Verify config: `cat /etc/sysctl.conf | grep bbr`
   - Apply manually: `sysctl -p`

## Script Structure

```
vps-setup.sh
├── Color definitions and functions
├── Root privilege check
├── System update
├── Package installation
├── BBR configuration
├── SSH port setup
├── Xray installation and config
├── Xray service enablement (immediate start for validation)
├── Oh-My-Zsh installation
├── UFW firewall setup
└── System reboot
```

## Contributing

Feel free to submit issues or pull requests to improve this script. Common enhancement requests:

- Additional protocol support
- SSL certificate automation
- Advanced security configurations
- Multi-user setup options

## License

This script is provided as-is for educational and personal use. Please review the code and understand what it does before running on production systems.

## Support

For support, please:
1. Check the troubleshooting section above
2. Review script logs for error messages
3. Verify all prerequisites are met
4. Test on a non-production system first

---

**⚠️ Disclaimer**: This script modifies system configurations and security settings. Always understand the changes being made and test in a safe environment before use on critical systems.
