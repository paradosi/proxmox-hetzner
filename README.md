# Proxmox on Hetzner: Automated Deployment Solution

<div align="center">
  <img src="https://github.com/paradosi/proxmox-hetzner/raw/main/files/icons/proxmox.png" alt="Proxmox" height="64" style="margin-right: 20px"/> 
  <img src="https://github.com/paradosi/proxmox-hetzner/raw/main/files/icons/hetzner.png" alt="Hetzner" height="50" />
  
  <h3>Enterprise-Grade Proxmox Deployment for Hetzner Dedicated Servers</h3>
</div>

## Overview

This project provides an enterprise-ready solution for deploying Proxmox Virtual Environment on Hetzner dedicated servers **without requiring console access**. Our automated installation script handles the complex configuration process, allowing for rapid deployment of production-ready virtualization environments.

### Validated Hardware Platforms

| Server Series | Compatibility | Recommended Models |
|---------------|---------------|-------------------|
| AX Series | ✅ Fully Tested | AX-41, AX-51, AX-102 |
| EX Series | ✅ Compatible | EX-42, EX-52, EX-62 |
| SX Series | ✅ Compatible | SX-64, SX-128 |

> **Note:** This deployment solution has undergone extensive testing on AX-102 servers with ZFS RAID-1 configuration for optimal reliability and performance.

## Deployment Process

### Prerequisites

- A dedicated server from Hetzner (AX, EX, or SX series)
- Access to Hetzner Robot management interface
- SSH client

### Step 1: Prepare Rescue Environment

1. Log in to the [Hetzner Robot](https://robot.hetzner.com/server) management interface
2. Navigate to your server's **Rescue** tab
3. Configure the rescue system:
   - Operating system: **Linux**
   - Architecture: **64 bit**
   - Public key: *optional, recommended for enhanced security*
4. Click **Activate rescue system**
5. Navigate to the **Reset** tab
6. Select: **Execute an automatic hardware reset**
7. Confirm by clicking **Send**
8. Wait approximately 2-3 minutes for the server to boot into rescue mode
9. Connect via SSH to the rescue system using the provided credentials

### Step 2: Execute Deployment Script

Run the following command in the rescue system terminal:

```bash
bash <(curl -sSL https://github.com/paradosi/proxmox-hetzner/raw/main/scripts/pve-install.sh)
```

### Step 3: Configuration Process

The deployment script will guide you through the following configuration steps:

1. **Network Detection:** Automatically identifies and configures network interfaces
2. **Storage Configuration:** Detects available drives and configures optimal RAID setup
3. **System Settings:** Prompts for hostname, FQDN, timezone, and administrative credentials
4. **Installation:** Automated Proxmox VE deployment with ZFS configuration
5. **Network Configuration:** Sets up both IPv4 and IPv6 connectivity
6. **System Optimization:** Applies recommended system settings for production environments

## Post-Deployment Optimization

Execute these commands in your Proxmox environment to implement additional performance optimizations:

### System Updates and Essential Utilities

```bash
# Update system packages
apt update && apt -y upgrade && apt -y autoremove && pveupgrade && pveam update

# Install core utilities
apt install -y curl libguestfs-tools unzip iptables-persistent net-tools
```

### Subscription Notice Management

```bash
# Remove subscription notice
sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service
```

### ZFS Performance Optimization

For servers with 64GB+ RAM, implement these memory management optimizations:

```bash
# Configure network connection tracking
echo "nf_conntrack" >> /etc/modules
echo "net.netfilter.nf_conntrack_max=1048576" >> /etc/sysctl.d/99-proxmox.conf
echo "net.netfilter.nf_conntrack_tcp_timeout_established=28800" >> /etc/sysctl.d/99-proxmox.conf

# Optimize ZFS Adaptive Replacement Cache (ARC)
rm -f /etc/modprobe.d/zfs.conf
echo "options zfs zfs_arc_min=$[6 * 1024*1024*1024]" >> /etc/modprobe.d/99-zfs.conf
echo "options zfs zfs_arc_max=$[12 * 1024*1024*1024]" >> /etc/modprobe.d/99-zfs.conf
update-initramfs -u
```

## Accessing Your Environment

After successful deployment:

1. Access the Proxmox Web Management Interface: 
   ```
   https://YOUR-SERVER-IP:8006
   ```

2. Log in with:
   - Username: `root`
   - Password: *your configured password*

3. Review the automatically generated `notes.txt` file for specific environment details

## Additional Resources

### Documentation

- [Comprehensive Deployment Guide](https://github.com/paradosi/proxmox-hetzner/wiki/Deployment-Guide)
- [Performance Tuning Guide](https://github.com/paradosi/proxmox-hetzner/wiki/Performance-Tuning)
- [Troubleshooting](https://github.com/paradosi/proxmox-hetzner/wiki/Troubleshooting)

### Community Resources

- [Proxmox Helper Scripts](https://tteck.github.io/Proxmox/)
- [Proxmox Tools Collection](https://github.com/extremeshok/xshok-proxmox)
- [Hetzner-Specific Optimizations](https://github.com/extremeshok/xshok-proxmox/tree/master/hetzner)

### Security Resources

- [Proxmox Firewall Configuration Guide](https://www.virtualizationhowto.com/2022/10/proxmox-firewall-rules-configuration/)
- [Firewalld on Debian Guide](https://computingforgeeks.com/how-to-install-and-configure-firewalld-on-debian/)

---

<div align="center">
  <p><strong>Proxmox on Hetzner</strong> — Enterprise-grade virtualization infrastructure, simplified</p>
  <p>© 2025 • <a href="https://github.com/paradosi">Paradosi</a></p>
</div>