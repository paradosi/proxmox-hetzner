<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Proxmox on Hetzner: Automated Deployment Solution</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #e0e0e0; /* Darker grey background */
        }
        .container {
            max-width: 900px;
            margin: 0 auto;
            background-color: #f8f8f8;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1, h2, h3 {
            color: #333;
        }
        h1 {
            text-align: center;
            margin-bottom: 30px;
        }
        code {
            background-color: #f0f0f0;
            padding: 2px 5px;
            border-radius: 3px;
            font-family: monospace;
        }
        pre {
            background-color: #f0f0f0;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            font-family: monospace;
        }
        .center {
            text-align: center;
        }
        .logos {
            display: flex;
            justify-content: center;
            align-items: center;
            margin: 20px 0;
        }
        .logos img {
            margin: 0 20px;
        }
        .footer {
            margin-top: 40px;
            text-align: center;
            color: #666;
            padding-top: 20px;
            border-top: 1px solid #ddd;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Proxmox on Hetzner: Automated Deployment Solution</h1>
        
        <div class="center">
            <div class="logos">
                <img src="https://github.com/paradosi/proxmox-hetzner/blob/main/files/icons/proxmox.png" alt="Proxmox" height="120">
            </div>
            <div class="logos">
                <img src="https://github.com/paradosi/proxmox-hetzner/raw/main/files/icons/hetzner.png" alt="Hetzner" height="50">
            </div>
            <h3>Enterprise-Grade Proxmox Deployment for Hetzner Dedicated Servers</h3>
        </div>

        <h2>Overview</h2>
        <p>This project provides an enterprise-ready solution for deploying Proxmox Virtual Environment on Hetzner dedicated servers <strong>without requiring console access</strong>. Our automated installation script handles the complex configuration process, allowing for rapid deployment of production-ready virtualization environments.</p>

        <h2>Deployment Process</h2>
        
        <h3>Prerequisites</h3>
        <ul>
            <li>A dedicated server from Hetzner</li>
            <li>Access to Hetzner Robot management interface</li>
            <li>SSH client</li>
        </ul>

        <h3>Step 1: Prepare Rescue Environment</h3>
        <ol>
            <li>Log in to the <a href="https://robot.hetzner.com/server">Hetzner Robot</a> management interface</li>
            <li>Navigate to your server's <strong>Rescue</strong> tab</li>
            <li>Configure the rescue system:
                <ul>
                    <li>Operating system: <strong>Linux</strong></li>
                    <li>Architecture: <strong>64 bit</strong></li>
                    <li>Public key: <em>optional, recommended for enhanced security</em></li>
                </ul>
            </li>
            <li>Click <strong>Activate rescue system</strong></li>
            <li>Navigate to the <strong>Reset</strong> tab</li>
            <li>Select: <strong>Execute an automatic hardware reset</strong></li>
            <li>Confirm by clicking <strong>Send</strong></li>
            <li>Wait approximately 2-3 minutes for the server to boot into rescue mode</li>
            <li>Connect via SSH to the rescue system using the provided credentials</li>
        </ol>

        <h3>Step 2: Execute Deployment Script</h3>
        <p>Run the following command in the rescue system terminal:</p>
        <pre>bash &lt;(curl -sSL https://github.com/paradosi/proxmox-hetzner/raw/main/scripts/pve-install.sh)</pre>

        <h3>Step 3: Configuration Process</h3>
        <p>The deployment script will guide you through the following configuration steps:</p>
        <ol>
            <li><strong>Network Detection:</strong> Automatically identifies and configures network interfaces</li>
            <li><strong>Storage Configuration:</strong> Detects available drives and configures optimal RAID setup</li>
            <li><strong>System Settings:</strong> Prompts for hostname, FQDN, timezone, and administrative credentials</li>
            <li><strong>Installation:</strong> Automated Proxmox VE deployment with ZFS configuration</li>
            <li><strong>Network Configuration:</strong> Sets up both IPv4 and IPv6 connectivity</li>
            <li><strong>System Optimization:</strong> Applies recommended system settings for production environments</li>
        </ol>

        <h2>Post-Deployment Optimization</h2>
        <p>Execute these commands in your Proxmox environment to implement additional performance optimizations:</p>

        <h3>System Updates and Essential Utilities</h3>
        <pre># Update system packages
apt update && apt -y upgrade && apt -y autoremove && pveupgrade && pveam update

# Install core utilities
apt install -y curl libguestfs-tools unzip iptables-persistent net-tools</pre>

        <h3>Subscription Notice Management</h3>
        <pre># Remove subscription notice
sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service</pre>

        <h3>ZFS Performance Optimization</h3>
        <p>For servers with 64GB+ RAM, implement these memory management optimizations:</p>
        <pre># Configure network connection tracking
echo "nf_conntrack" >> /etc/modules
echo "net.netfilter.nf_conntrack_max=1048576" >> /etc/sysctl.d/99-proxmox.conf
echo "net.netfilter.nf_conntrack_tcp_timeout_established=28800" >> /etc/sysctl.d/99-proxmox.conf

# Optimize ZFS Adaptive Replacement Cache (ARC)
rm -f /etc/modprobe.d/zfs.conf
echo "options zfs zfs_arc_min=$[6 * 1024*1024*1024]" >> /etc/modprobe.d/99-zfs.conf
echo "options zfs zfs_arc_max=$[12 * 1024*1024*1024]" >> /etc/modprobe.d/99-zfs.conf
update-initramfs -u</pre>

        <h2>Accessing Your Environment</h2>
        <p>After successful deployment:</p>
        <ol>
            <li>Access the Proxmox Web Management Interface: 
                <pre>https://YOUR-SERVER-IP:8006</pre>
            </li>
            <li>Log in with:
                <ul>
                    <li>Username: <code>root</code></li>
                    <li>Password: <em>your configured password</em></li>
                </ul>
            </li>
            <li>Review the automatically generated <code>notes.txt</code> file for specific environment details</li>
        </ol>

        <h2>Additional Resources</h2>

        <h3>Documentation</h3>
        <ul>
            <li><a href="https://github.com/paradosi/proxmox-hetzner/wiki/Deployment-Guide">Comprehensive Deployment Guide</a></li>
            <li><a href="https://github.com/paradosi/proxmox-hetzner/wiki/Performance-Tuning">Performance Tuning Guide</a></li>
            <li><a href="https://github.com/paradosi/proxmox-hetzner/wiki/Troubleshooting">Troubleshooting</a></li>
        </ul>

        <h3>Community Resources</h3>
        <ul>
            <li><a href="https://tteck.github.io/Proxmox/">Proxmox Helper Scripts</a></li>
            <li><a href="https://github.com/extremeshok/xshok-proxmox">Proxmox Tools Collection</a></li>
            <li><a href="https://github.com/extremeshok/xshok-proxmox/tree/master/hetzner">Hetzner-Specific Optimizations</a></li>
        </ul>

        <h3>Security Resources</h3>
        <ul>
            <li><a href="https://www.virtualizationhowto.com/2022/10/proxmox-firewall-rules-configuration/">Proxmox Firewall Configuration Guide</a></li>
            <li><a href="https://computingforgeeks.com/how-to-install-and-configure-firewalld-on-debian/">Firewalld on Debian Guide</a></li>
        </ul>

        <div class="footer">
            <p><strong>Proxmox on Hetzner</strong> — Enterprise-grade virtualization infrastructure, simplified</p>
            <p>© 2025 • <a href="https://github.com/paradosi">Paradosi</a></p>
        </div>
    </div>
</body>
</html>