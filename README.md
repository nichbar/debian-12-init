# VPS Setup Script for Debian 12

An interactive, robust Bash script that automates the initial setup and configuration of a fresh Debian 12 VPS with network optimization, custom SSH port management, SSH public key hardening, Xray core installation, terminal enhancements, and UFW firewall protection.

## Quick Install

### Recommended (Process Substitution)

Process substitution connects your terminal's TTY so interactive prompts and the `nano` editor work smoothly:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/nichbar/debian-12-init/main/vps-setup.sh)
```

### Alternative (Download & Run)

```bash
curl -sSL -O https://raw.githubusercontent.com/nichbar/debian-12-init/main/vps-setup.sh
chmod +x vps-setup.sh
sudo ./vps-setup.sh
```

> **Note**: Avoid running via `curl ... | bash` directly, as piping stdin bypasses terminal control needed for interactive prompts and text editors.

---

## Features

- **System Package Management**: Offers an interactive prompt to perform a full system update (apt update & upgrade) or skip package upgrades while refreshing indexes, then installs essential utilities (`curl`, `wget`, `net-tools`, `ufw`, `zsh`, `git`, `procps`, `nano`, `openssh-client`).
- **BBR TCP Optimization**: Configures BBR congestion control via `/etc/sysctl.d/99-bbr.conf` idempotently, with fallback detection for container environments (OpenVZ/LXC).
- **SSH Hardening & Public Key Authentication**:
  - Interactive custom port prompt with strict input validation (1–65535).
  - **SSH Public Key Setup**: Prompts to paste a public SSH key, validates its format via `ssh-keygen`, and adds it to `/root/.ssh/authorized_keys`.
  - **Automated Password Hardening**: Once an SSH key is set, the script immediately disables password authentication (`PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin prohibit-password`).
  - Handles Debian 12 **systemd socket activation (`ssh.socket`)** via drop-in override (`listen.conf`), preventing port lockout.
  - Updates `/etc/ssh/sshd_config` and `/etc/ssh/sshd_config.d/01-vps-setup.conf`.
  - Runs pre-flight configuration test (`sshd -t`) before applying changes.
- **Xray Core**:
  - Installs the latest stable Xray core via the official XTLS installer.
  - Pre-populates a valid starter configuration if none exists.
  - Opens `nano` for custom configuration review or editing.
  - Automatically validates syntax with `xray run -test -c ...` in a loop, allowing you to fix errors before starting the service.
- **Oh-My-Zsh & Zsh Default Shell**: Installs Oh-My-Zsh unattended and updates root's default login shell to `/bin/zsh`.
- **UFW Firewall**: Sets default deny policy for incoming traffic, allowing only your configured SSH and Xray ports.
- **SynBlocker (SYN Flood Protection)**: Optional integration of SynBlocker (https://github.com/nichbar/SynBlocker) to monitor TCP SYN_RECV connections and automatically ban attacking /24 subnets via UFW.
- **Safe Reboot**: Warns you to verify SSH connectivity in a separate terminal before exiting and prompts for confirmation before rebooting.

---

## Requirements

- **Operating System**: Debian 12 (Bookworm)
- **Privileges**: Root access (`sudo` or logged in as `root`)
- **Network**: Internet access to download packages and GitHub assets

---

## Repository Structure

```
debian-12-init/
├── vps-setup.sh      # Main setup script
└── README.md         # Documentation
```

If deploying to your own GitHub fork, update the raw URL:
```bash
bash <(curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/vps-setup.sh)
```

---

## Script Workflow

The script guides you through the following sequential steps:

1. **Root & TTY Detection**: Verifies root execution and re-attaches `/dev/tty` if needed.
2. **System Update Option**: Prompts whether to perform a full system update (`apt update & upgrade`) or skip package upgrades while refreshing indexes for prerequisites.
3. **Dependencies**: Installs `curl`, `wget`, `net-tools`, `ufw`, `zsh`, `git`, `procps`, `nano`, and `openssh-client`.
4. **BBR TCP Optimization**: Loads `tcp_bbr` and applies `fq` + `bbr` via `/etc/sysctl.d/99-bbr.conf`.
5. **SSH Port & Key Hardening**:
   - Prompts for your desired SSH port (default: 22).
   - Prompts whether to add a public SSH key (e.g. `ssh-ed25519 AAAAC3...`).
   - Validates the key format using `ssh-keygen` and saves it to `/root/.ssh/authorized_keys` with `600` permissions.
   - **If a key is configured**: Disables password authentication (`PasswordAuthentication no`, `PermitRootLogin prohibit-password`, `KbdInteractiveAuthentication no`).
   - **If skipped**: Keeps password login enabled to prevent lockout.
   - Configures `/etc/systemd/system/ssh.socket.d/listen.conf` for Debian 12 socket activation.
   - Restarts SSH services/sockets and validates syntax with `sshd -t`.
6. **Xray Installation & Setup**:
   - Prompts for Xray port (default: 443), ensuring it does not collide with your SSH port.
   - Installs the latest stable Xray core.
   - Opens `nano` with a pre-populated template for your inspection.
   - Validates JSON configuration with `xray run -test -c ...`.
   - Enables and starts the `xray` service.
7. **Oh-My-Zsh**: Installs Oh-My-Zsh and sets root's default shell to Zsh.
8. **UFW Firewall**: Resets rules, applies default deny incoming, and allows the chosen SSH and Xray ports.
9. **SynBlocker (Optional)**: Prompts to install the SynBlocker SYN flood mitigation tool, setting up automated cron monitoring and providing the `synblocker` CLI.
10. **Verification & Optional Reboot**: Displays setup summary and asks whether to reboot now.

---

## File Locations

| Component | Path |
| :--- | :--- |
| **SSH Authorized Keys** | `/root/.ssh/authorized_keys` |
| **SSH Daemon Config** | `/etc/ssh/sshd_config` & `/etc/ssh/sshd_config.d/01-vps-setup.conf` |
| **Systemd SSH Socket Drop-in** | `/etc/systemd/system/ssh.socket.d/listen.conf` |
| **Xray Configuration** | `/usr/local/etc/xray/config.json` |
| **BBR Sysctl Config** | `/etc/sysctl.d/99-bbr.conf` |
| **Oh-My-Zsh Installation** | `/root/.oh-my-zsh` |
| **UFW Rules** | `/etc/ufw/user.rules` |
| **SynBlocker Location** | `/root/SyncBlocker/` & `/usr/local/bin/synblocker` |
| **SynBlocker Logs** | `/var/log/syn-flood/` |
| **SynBlocker Cron Job** | `/etc/cron.d/syn-monitor` |

---

## Post-Setup Verification

1. **Verify SSH Access**:
   Always test in a **new terminal tab** before disconnecting your current session:
   - **If SSH key was configured:**
     ```bash
     ssh -i ~/.ssh/id_ed25519 -p YOUR_SSH_PORT root@YOUR_SERVER_IP
     ```
   - **If password login was kept:**
     ```bash
     ssh -p YOUR_SSH_PORT root@YOUR_SERVER_IP
     ```

2. **Check Xray Status**:
   ```bash
   systemctl status xray
   journalctl -u xray -e
   ```

3. **Validate Xray Configuration**:
   ```bash
   xray run -test -c /usr/local/etc/xray/config.json
   ```

4. **Verify Firewall Rules**:
   ```bash
   ufw status verbose
   ```

5. **Verify BBR Congestion Control**:
   ```bash
   sysctl net.ipv4.tcp_congestion_control
   ```

6. **Verify Active Listening Ports**:
   ```bash
   ss -tulpn
   ```

7. **Check SynBlocker Status (if installed)**:
   ```bash
   synblocker status
   ```
   Inspect ban logs:
   ```bash
   synblocker logs
   ```

---

## Security Best Practices

- **SSH Keys**: Disabling password authentication protects against automated brute-force attacks. Always keep a secure backup of your private key.
- **Firewall**: Ensure non-essential ports remain blocked. Only open additional ports when necessary using `ufw allow <port>/<protocol>`.
- **Maintenance**: Keep your system updated periodically with `apt update && apt upgrade -y`.

---

## Troubleshooting

### 1. SSH Connection Refused or Permission Denied
- If you disabled passwords, ensure you are specifying your private key:
  ```bash
  ssh -i /path/to/private_key -p YOUR_SSH_PORT root@YOUR_SERVER_IP
  ```
- Check if systemd socket activation is active:
  ```bash
  systemctl status ssh.socket
  ss -tulpn | grep ssh
  ```
- Verify UFW allows your custom port:
  ```bash
  ufw status
  ```

### 2. Xray Service Fails to Start
- Validate your JSON configuration for syntax or schema errors:
  ```bash
  xray run -test -c /usr/local/etc/xray/config.json
  ```
- Inspect systemd journal logs:
  ```bash
  journalctl -u xray -e --no-pager
  ```

### 3. BBR Congestion Control Not Active
- On standard KVM/bare-metal VPS:
  ```bash
  modprobe tcp_bbr
  sysctl -p /etc/sysctl.d/99-bbr.conf
  ```
- *Note:* In OpenVZ or shared LXC container environments, kernel modules cannot be loaded by container guests.

---

## License

This project is open source and provided under the MIT License. Use at your own risk. Always test in a staging environment before running on production servers.
