#!/usr/bin/env bash
#=========================================================================
# Proxmox VE Auto-Installation Script
# Forked from https://github.com/ariadata/proxmox-hetzner :: many thanks
# Version: 1.0.0
# Author: paradosi
# License: MIT
#
# Description:
#   This script automates the installation of Proxmox VE on bare metal servers.
#   It detects network interfaces, configures RAID, and sets up the system
#   according to best practices.
#=========================================================================

# Strict mode
set -euo pipefail
IFS=$'\n\t'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" || exit 1

# Log file
LOG_FILE="/var/log/proxmox-installer.log"
mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

# Configuration directory
CONFIG_DIR="${SCRIPT_DIR}/config"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
mkdir -p "${CONFIG_DIR}" "${TEMPLATE_DIR}"

#=========================================================================
# Color definitions
#=========================================================================
readonly C_RESET="\033[0m"
readonly C_RED="\033[1;31m"
readonly C_GREEN="\033[1;32m"
readonly C_YELLOW="\033[1;33m"
readonly C_BLUE="\033[1;34m"
readonly C_PURPLE="\033[1;35m"
readonly C_CYAN="\033[1;36m"
readonly C_WHITE="\033[1;37m"

#=========================================================================
# Configuration Variables - Will be populated during script execution
#=========================================================================
INTERFACE_NAME=""
MAIN_IPV4_CIDR=""
MAIN_IPV4=""
MAIN_IPV4_GW=""
MAC_ADDRESS=""
IPV6_CIDR=""
MAIN_IPV6=""
FIRST_IPV6_CIDR=""

FIRST_DRIVE=""
SECOND_DRIVE=""
FIRST_DRIVE_PATH=""
SECOND_DRIVE_PATH=""
RAID_LEVEL=""
ZFS_RAID_TYPE=""

HOSTNAME=""
FQDN=""
TIMEZONE=""
EMAIL=""
PRIVATE_SUBNET=""
PRIVATE_IP=""
PRIVATE_IP_CIDR=""
NEW_ROOT_PASSWORD=""

QEMU_PID=""
PROXMOX_ISO_URL=""

#=========================================================================
# Logger Functions
#=========================================================================
log() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${C_BLUE}[INFO]${C_RESET} $*"
}

log_success() {
    log "${C_GREEN}[SUCCESS]${C_RESET} $*"
}

log_warning() {
    log "${C_YELLOW}[WARNING]${C_RESET} $*"
}

log_error() {
    log "${C_RED}[ERROR]${C_RESET} $*"
}

log_section() {
    log "\n${C_PURPLE}=== $* ===${C_RESET}"
}

#=========================================================================
# Utility Functions
#=========================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

confirm_proceed() {
    local message="$1"
    local default="${2:-y}"
    
    local prompt
    if [[ "${default}" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    read -r -p "${message} ${prompt} " response
    response="${response:-${default}}"
    
    if [[ "${response,,}" =~ ^(yes|y)$ ]]; then
        return 0
    else
        return 1
    fi
}

show_banner() {
    clear
    cat << "EOF"
 ____                                 __   _______ 
|  _ \ _ __ _____  ___ __ ___   ___ __ \ \ / / ____|
| |_) | '__/ _ \ \/ / '_ ` _ \ / _ \_  / \ V /|  _|  
|  __/| | | (_) >  <| | | | | | (_) / /   | | | |___ 
|_|   |_|  \___/_/\_\_| |_| |_|\___/___/  |_| |_____|
                                                   
 Auto-Installation Script                  
EOF
    echo -e "${C_BLUE}Version 1.0.0${C_RESET}\n"
    echo -e "${C_YELLOW}This script will automate the installation of Proxmox VE.${C_RESET}"
    echo -e "${C_YELLOW}It will detect your network, configure storage, and set up the system.${C_RESET}\n"
}

#=========================================================================
# Detection and Input Functions
#=========================================================================
get_system_inputs() {
    log_section "System Configuration"
    
    # Get default interface name and available alternative names
    local DEFAULT_INTERFACE
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$DEFAULT_INTERFACE" ]; then
        DEFAULT_INTERFACE=$(udevadm info -e | grep -m1 -A 20 ^P.*eth0 | grep ID_NET_NAME_PATH | cut -d'=' -f2)
    fi
    
    # Get all available interfaces and their altnames
    local AVAILABLE_ALTNAMES
    AVAILABLE_ALTNAMES=$(ip -d link show | grep -v "lo:" | grep -E '(^[0-9]+:|altname)' | awk '/^[0-9]+:/ {interface=$2; gsub(/:/, "", interface); printf "%s", interface} /altname/ {printf ", %s", $2} END {print ""}' | sed 's/, $//')
    
    # Set INTERFACE_NAME to default if not already set
    if [ -z "$INTERFACE_NAME" ]; then
        INTERFACE_NAME="$DEFAULT_INTERFACE"
    fi
    
    log_info "Available network interfaces: ${AVAILABLE_ALTNAMES}"
    read -e -p "Interface name: " -i "$INTERFACE_NAME" INTERFACE_NAME
    
    # Now get network information based on the selected interface
    MAIN_IPV4_CIDR=$(ip address show "$INTERFACE_NAME" | grep global | grep "inet " | xargs | cut -d" " -f2)
    MAIN_IPV4=$(echo "$MAIN_IPV4_CIDR" | cut -d'/' -f1)
    MAIN_IPV4_GW=$(ip route | grep default | xargs | cut -d" " -f3)
    MAC_ADDRESS=$(ip link show "$INTERFACE_NAME" | awk '/ether/ {print $2}')
    IPV6_CIDR=$(ip address show "$INTERFACE_NAME" | grep global | grep "inet6 " | xargs | cut -d" " -f2)
    MAIN_IPV6=$(echo "$IPV6_CIDR" | cut -d'/' -f1)
    
    # Set a default value for FIRST_IPV6_CIDR even if IPV6_CIDR is empty
    if [ -n "$IPV6_CIDR" ]; then
        FIRST_IPV6_CIDR="$(echo "$IPV6_CIDR" | cut -d'/' -f1 | cut -d':' -f1-4):1::1/80"
    else
        FIRST_IPV6_CIDR=""
    fi
    
    # Display detected information
    log_info "Network Information:"
    echo "  Interface Name    : $INTERFACE_NAME"
    echo "  IPv4 CIDR         : $MAIN_IPV4_CIDR"
    echo "  IPv4 Address      : $MAIN_IPV4"
    echo "  IPv4 Gateway      : $MAIN_IPV4_GW"
    echo "  MAC Address       : $MAC_ADDRESS"
    echo "  IPv6 CIDR         : $IPV6_CIDR"
    echo "  IPv6 Address      : $MAIN_IPV6"
    
    # Configure storage
    log_section "Storage Configuration"
    
    # Get list of disk devices
    local AVAILABLE_DRIVES
    AVAILABLE_DRIVES=$(lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop\|sr\|fd" | sort)
    
    if [ -z "$AVAILABLE_DRIVES" ]; then
        log_error "No suitable storage drives detected! Exiting."
        exit 1
    fi
    
    # Show available drives
    log_info "Available storage drives:"
    lsblk -d -o NAME,SIZE,MODEL,SERIAL | grep -v "loop\|sr\|fd"
    echo ""
    
    # Get first drive
    local default_first_drive
    default_first_drive=$(echo "$AVAILABLE_DRIVES" | head -n1 | awk '{print $1}')
    read -e -p "Select first drive for Proxmox installation: " -i "$default_first_drive" FIRST_DRIVE
    
    # Validate first drive exists
    if [ ! -b "/dev/$FIRST_DRIVE" ]; then
        log_error "Drive /dev/$FIRST_DRIVE does not exist! Exiting."
        exit 1
    fi
    
    # Get second drive
    local filtered_drives
    filtered_drives=$(echo "$AVAILABLE_DRIVES" | grep -v "^$FIRST_DRIVE ")
    if [ -z "$filtered_drives" ]; then
        log_error "No additional drives available for RAID! Exiting."
        exit 1
    fi
    
    local default_second_drive
    default_second_drive=$(echo "$filtered_drives" | head -n1 | awk '{print $1}')
    read -e -p "Select second drive for Proxmox installation: " -i "$default_second_drive" SECOND_DRIVE
    
    # Validate second drive exists
    if [ ! -b "/dev/$SECOND_DRIVE" ]; then
        log_error "Drive /dev/$SECOND_DRIVE does not exist! Exiting."
        exit 1
    fi
    
    # Prompt for RAID level
    echo -e "\n${C_YELLOW}RAID Configuration:${C_RESET}"
    echo "  RAID0: Stripes data across drives for maximum space and performance (no redundancy)"
    echo "  RAID1: Mirrors data across drives for redundancy (half the total space)"
    read -e -p "Select RAID level (0 or 1): " -i "1" RAID_LEVEL
    
    # Validate RAID level
    if [[ "$RAID_LEVEL" != "0" && "$RAID_LEVEL" != "1" ]]; then
        log_warning "Invalid RAID level! Must be 0 or 1. Defaulting to RAID1."
        RAID_LEVEL="1"
    fi
    
    # Store full paths and RAID config
    FIRST_DRIVE_PATH="/dev/$FIRST_DRIVE"
    SECOND_DRIVE_PATH="/dev/$SECOND_DRIVE"
    ZFS_RAID_TYPE="raid$RAID_LEVEL"
    
    log_success "Selected drives: $FIRST_DRIVE_PATH and $SECOND_DRIVE_PATH with RAID$RAID_LEVEL"
    
    # System configuration
    log_section "System Settings"
    
    # Get user input for other configuration
    read -e -p "Hostname: " -i "proxmox-server" HOSTNAME
    read -e -p "FQDN: " -i "$HOSTNAME.example.com" FQDN
    read -e -p "Timezone: " -i "UTC" TIMEZONE
    read -e -p "Admin email: " -i "admin@example.com" EMAIL
    read -e -p "Private subnet: " -i "10.10.10.0/24" PRIVATE_SUBNET
    
    # Password input with masking and confirmation
    while true; do
        read -s -p "Root password: " NEW_ROOT_PASSWORD
        echo
        if [[ -z "$NEW_ROOT_PASSWORD" ]]; then
            log_error "Password cannot be empty. Please try again."
            continue
        fi
        
        read -s -p "Confirm password: " PASSWORD_CONFIRM
        echo
        
        if [[ "$NEW_ROOT_PASSWORD" == "$PASSWORD_CONFIRM" ]]; then
            break
        else
            log_error "Passwords do not match. Please try again."
        fi
    done
    
    # Get the network prefix (first three octets) from PRIVATE_SUBNET
    local PRIVATE_CIDR
    PRIVATE_CIDR=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    # Append .1 to get the first IP in the subnet
    PRIVATE_IP="${PRIVATE_CIDR}.1"
    # Get the subnet mask length
    local SUBNET_MASK
    SUBNET_MASK=$(echo "$PRIVATE_SUBNET" | cut -d'/' -f2)
    # Create the full CIDR notation for the first IP
    PRIVATE_IP_CIDR="${PRIVATE_IP}/${SUBNET_MASK}"
    
    log_info "Private network configuration:"
    echo "  Subnet: $PRIVATE_SUBNET"
    echo "  First IP (CIDR): $PRIVATE_IP_CIDR"
    
    # Save configuration to file for reference
    {
        echo "# Proxmox Installation Configuration"
        echo "# Generated on: $(date)"
        echo "HOSTNAME=$HOSTNAME"
        echo "FQDN=$FQDN"
        echo "INTERFACE_NAME=$INTERFACE_NAME"
        echo "MAIN_IPV4=$MAIN_IPV4"
        echo "MAIN_IPV4_CIDR=$MAIN_IPV4_CIDR"
        echo "MAIN_IPV4_GW=$MAIN_IPV4_GW"
        echo "PRIVATE_SUBNET=$PRIVATE_SUBNET"
        echo "PRIVATE_IP_CIDR=$PRIVATE_IP_CIDR"
        echo "FIRST_DRIVE=$FIRST_DRIVE"
        echo "SECOND_DRIVE=$SECOND_DRIVE"
        echo "RAID_LEVEL=$RAID_LEVEL"
    } > "${CONFIG_DIR}/installation.conf"
    
    log_success "Configuration saved to ${CONFIG_DIR}/installation.conf"
    
    # Confirm installation
    echo
    if ! confirm_proceed "Ready to proceed with installation?"; then
        log_info "Installation aborted by user"
        exit 0
    fi
}

#=========================================================================
# Installation Functions
#=========================================================================
prepare_packages() {
    log_section "Installing Required Packages"
    
    log_info "Adding Proxmox repository..."
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" | tee /etc/apt/sources.list.d/pve.list
    
    log_info "Fetching Proxmox GPG key..."
    curl -fsSL -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg
    
    log_info "Updating package lists and installing required packages..."
    apt-get clean && apt-get update
    apt-get install -y --no-install-recommends \
        proxmox-auto-install-assistant \
        xorriso \
        ovmf \
        wget \
        sshpass \
        ca-certificates \
        curl \
        lsb-release \
        gnupg2
    
    log_success "Required packages installed"
}

download_proxmox_iso() {
    log_section "Downloading Proxmox VE ISO"
    
    local base_url="https://enterprise.proxmox.com/iso/"
    log_info "Detecting latest Proxmox VE ISO..."
    
    local latest_iso
    latest_iso=$(curl -s "$base_url" | grep -oP 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | sort -V | tail -n1)
    
    if [[ -z "$latest_iso" ]]; then
        log_error "Failed to detect latest Proxmox VE ISO. Exiting."
        exit 1
    fi
    
    PROXMOX_ISO_URL="${base_url}${latest_iso}"
    log_info "Latest Proxmox VE ISO: ${latest_iso}"
    log_info "Downloading from: ${PROXMOX_ISO_URL}"
    
    wget --progress=bar:force -O pve.iso "$PROXMOX_ISO_URL"
    
    if [[ ! -f "pve.iso" ]]; then
        log_error "Failed to download Proxmox ISO. Exiting."
        exit 1
    fi
    
    log_success "Proxmox VE ISO downloaded successfully"
}

make_answer_toml() {
    log_section "Creating Autoinstallation Configuration"
    
    log_info "Generating answer.toml for unattended installation..."
    cat <<EOF > answer.toml
# Proxmox VE Autoinstall Configuration
# Generated on: $(date)

[global]
    keyboard = "en-us"
    country = "us"
    fqdn = "$FQDN"
    mailto = "$EMAIL"
    timezone = "$TIMEZONE"
    root_password = "$NEW_ROOT_PASSWORD"
    reboot_on_error = false

[network]
    source = "from-dhcp"

[disk-setup]
    filesystem = "zfs"
    zfs.raid = "$ZFS_RAID_TYPE"
    disk_list = ["/dev/vda", "/dev/vdb"]

EOF
    log_success "answer.toml created successfully"
}

make_autoinstall_iso() {
    log_section "Creating Autoinstallation ISO"
    
    log_info "Preparing autoinstallation ISO..."
    proxmox-auto-install-assistant prepare-iso pve.iso \
        --fetch-from iso \
        --answer-file answer.toml \
        --output pve-autoinstall.iso
    
    if [[ ! -f "pve-autoinstall.iso" ]]; then
        log_error "Failed to create autoinstallation ISO. Exiting."
        exit 1
    }
    
    log_success "Autoinstallation ISO created successfully: pve-autoinstall.iso"
}

is_uefi_mode() {
    [ -d /sys/firmware/efi ]
}

install_proxmox() {
    log_section "Starting Proxmox VE Installation"
    
    local UEFI_OPTS=""
    if is_uefi_mode; then
        UEFI_OPTS="-bios /usr/share/ovmf/OVMF.fd"
        log_info "UEFI mode detected, booting with UEFI firmware"
    else
        log_info "UEFI not detected, booting in legacy mode"
    fi
    
    log_warning "The installation process will take 5-10 minutes"
    log_warning "Do NOT interact with the system during installation"
    
    log_info "Starting QEMU for installation..."
    
    # Create progress indicator function
    (
        i=0
        while :; do
            i=$((i+1))
            echo -ne "\r${C_BLUE}Installation in progress [${i}s]${C_RESET}"
            sleep 1
        done
    ) &
    PROGRESS_PID=$!
    
    # Run QEMU silently
    qemu-system-x86_64 \
        -enable-kvm $UEFI_OPTS \
        -cpu host -smp 4 -m 4096 \
        -boot d -cdrom ./pve-autoinstall.iso \
        -drive file=$FIRST_DRIVE_PATH,format=raw,media=disk,if=virtio \
        -drive file=$SECOND_DRIVE_PATH,format=raw,media=disk,if=virtio \
        -no-reboot -display none > /dev/null 2>&1
    
    # Kill progress indicator
    kill $PROGRESS_PID 2>/dev/null || true
    wait $PROGRESS_PID 2>/dev/null || true
    echo -e "\r${C_GREEN}Installation phase completed${C_RESET}            "
    
    log_success "Proxmox VE base installation completed"
}

boot_proxmox_with_port_forwarding() {
    log_section "Post-Installation Configuration"
    
    log_info "Booting installed Proxmox VE with SSH port forwarding"
    
    local UEFI_OPTS=""
    if is_uefi_mode; then
        UEFI_OPTS="-bios /usr/share/ovmf/OVMF.fd"
        log_info "UEFI mode detected, booting with UEFI firmware"
    else
        log_info "UEFI not detected, booting in legacy mode"
    fi
    
    # Start QEMU in background with port forwarding
    nohup qemu-system-x86_64 -enable-kvm $UEFI_OPTS \
        -cpu host -device e1000,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::5555-:22 \
        -smp 4 -m 4096 \
        -drive file=$FIRST_DRIVE_PATH,format=raw,media=disk,if=virtio \
        -drive file=$SECOND_DRIVE_PATH,format=raw,media=disk,if=virtio \
        > qemu_output.log 2>&1 &
    
    QEMU_PID=$!
    log_info "QEMU started with PID: $QEMU_PID"
    
    # Wait for SSH to become available on port 5555
    log_info "Waiting for SSH to become available..."
    echo -n "  "
    
    local ssh_available=false
    for i in {1..60}; do
        if nc -z localhost 5555; then
            ssh_available=true
            echo -e "\n${C_GREEN}SSH is available on port 5555${C_RESET}"
            break
        fi
        echo -n "."
        sleep 5
    done
    
    if ! $ssh_available; then
        log_error "SSH did not become available after 5 minutes. Check the system manually."
        return 1
    fi
    
    # Give the system a few more seconds to fully boot
    sleep 10
    
    return 0
}

make_template_files() {
    log_section "Preparing Configuration Templates"
    
    log_info "Downloading template files..."
    mkdir -p ./template_files

    wget -q -O ./template_files/99-proxmox.conf https://github.com/paradosi/proxmox-hetzner/raw/refs/heads/main/files/template_files/99-proxmox.conf
    wget -q -O ./template_files/hosts https://github.com/paradosi/proxmox-hetzner/raw/refs/heads/main/files/template_files/hosts
    wget -q -O ./template_files/interfaces https://github.com/paradosi/proxmox-hetzner/raw/refs/heads/main/files/template_files/interfaces
    wget -q -O ./template_files/sources.list https://github.com/paradosi/proxmox-hetzner/raw/refs/heads/main/files/template_files/sources.list

    # Process hosts file
    log_info "Processing hosts file..."
    sed -i "s|{{MAIN_IPV4}}|$MAIN_IPV4|g" ./template_files/hosts
    sed -i "s|{{FQDN}}|$FQDN|g" ./template_files/hosts
    sed -i "s|{{HOSTNAME}}|$HOSTNAME|g" ./template_files/hosts
    sed -i "s|{{MAIN_IPV6}}|$MAIN_IPV6|g" ./template_files/hosts

    # Process interfaces file
    log_info "Processing interfaces file..."
    sed -i "s|{{INTERFACE_NAME}}|$INTERFACE_NAME|g" ./template_files/interfaces
    sed -i "s|{{MAIN_IPV4_CIDR}}|$MAIN_IPV4_CIDR|g" ./template_files/interfaces
    sed -i "s|{{MAIN_IPV4_GW}}|$MAIN_IPV4_GW|g" ./template_files/interfaces
    sed -i "s|{{MAC_ADDRESS}}|$MAC_ADDRESS|g" ./template_files/interfaces
    sed -i "s|{{IPV6_CIDR}}|$IPV6_CIDR|g" ./template_files/interfaces
    sed -i "s|{{PRIVATE_IP_CIDR}}|$PRIVATE_IP_CIDR|g" ./template_files/interfaces
    sed -i "s|{{PRIVATE_SUBNET}}|$PRIVATE_SUBNET|g" ./template_files/interfaces
    sed -i "s|{{FIRST_IPV6_CIDR}}|$FIRST_IPV6_CIDR|g" ./template_files/interfaces

    log_success "Template files processed successfully"
}

configure_proxmox_via_ssh() {
    log_section "Configuring Proxmox VE"
    
    log_info "Preparing configuration files..."
    make_template_files
    
    # Clean up any old SSH known hosts entries
    ssh-keygen -f "/root/.ssh/known_hosts" -R "[localhost]:5555" 2>/dev/null || true
    
    # Function to execute SSH commands with proper error handling
    ssh_exec() {
        local cmd="$1"
        local desc="${2:-Executing command}"
        
        log_info "$desc..."
        if ! sshpass -p "$NEW_ROOT_PASSWORD" ssh -p 5555 -o StrictHostKeyChecking=no root@localhost "$cmd"; then
            log_error "Failed to execute: $cmd"
            return 1
        fi
        return 0
    }
    
    # Function to copy files via SCP with proper error handling
    scp_copy() {
        local src="$1"
        local dest="$2"
        local desc="${3:-Copying file}"
        
        log_info "$desc: $src -> $dest"
        if ! sshpass -p "$NEW_ROOT_PASSWORD" scp -P 5555 -o StrictHostKeyChecking=no "$src" "root@localhost:$dest"; then
            log_error "Failed to copy: $src -> $dest"
            return 1
        fi
        return 0
    }
    
    # Copy configuration files
    scp_copy "template_files/hosts" "/etc/hosts" "Setting up hosts file"
    scp_copy "template_files/interfaces" "/etc/network/interfaces" "Setting up network interfaces"
    scp_copy "template_files/99-proxmox.conf" "/etc/sysctl.d/99-proxmox.conf" "Setting up sysctl configuration"
    scp_copy "template_files/sources.list" "/etc/apt/sources.list" "Setting up package sources"
    
    # Disable enterprise repositories
    ssh_exec "sed -i 's/^\([^#].*\)/# \1/g' /etc/apt/sources.list.d/pve-enterprise.list" "Disabling PVE Enterprise repository"
    ssh_exec "sed -i 's/^\([^#].*\)/# \1/g' /etc/apt/sources.list.d/ceph.list" "Disabling Ceph Enterprise repository"
    
    # Set up DNS resolvers
    ssh_exec "echo -e 'nameserver 8.8.8.8\nnameserver 1.1.1.1\nnameserver 4.2.2.4\nnameserver 9.9.9.9' | tee /etc/resolv.conf" "Setting up DNS resolvers"
    
    # Set hostname
    ssh_exec "echo $HOSTNAME > /etc/hostname" "Setting hostname"
    
    # Disable unnecessary services
    ssh_exec "systemctl disable --now rpcbind rpcbind.socket" "Disabling rpcbind service"
    
    # Power off the VM
    log_info "Configuration complete, powering off VM..."
    sshpass -p "$NEW_ROOT_PASSWORD" ssh -p 5555 -o StrictHostKeyChecking=no root@localhost 'poweroff' || true
    
    # Wait for QEMU to exit
    log_info "Waiting for QEMU process to exit..."
    wait $QEMU_PID 2>/dev/null || true
    
    log_success "Post-installation configuration completed"
}

finalize_installation() {
    log_section "Installation Complete"
    
    # Display installation summary
    cat << EOF

${C_GREEN}Proxmox VE has been successfully installed!${C_RESET}

${C_YELLOW}Installation Summary:${C_RESET}
  Hostname         : $HOSTNAME
  FQDN             : $FQDN
  IPv4 Address     : $MAIN_IPV4
  Management URL   : https://${MAIN_IPV4}:8006
  Storage Config   : RAID${RAID_LEVEL} with ${FIRST_DRIVE} and ${SECOND_DRIVE}
  Private Network  : $PRIVATE_SUBNET

${C_YELLOW}Next Steps:${C_RESET}
  1. Reboot your server to boot into Proxmox VE
  2. Access the web interface at https://${MAIN_IPV4}:8006
  3. Log in with:
     - Username: root
     - Password: (the one you provided during installation)

${C_YELLOW}Log file:${C_RESET} ${LOG_FILE}
${C_YELLOW}Config backup:${C_RESET} ${CONFIG_DIR}/installation.conf

EOF
    
    # Ask if user wants to reboot
    if confirm_proceed "Would you like to reboot the system now?"; then
        log_info "Rebooting the system..."
        reboot
    else
        log_info "Reboot skipped. You can reboot manually when ready."
    fi
}

#=========================================================================
# Main Execution
#=========================================================================
main() {
    show_banner
    check_root
    
    # Execute installation steps
    get_system_inputs
    prepare_packages
    download_proxmox_iso
    make_answer_toml
    make_autoinstall_iso
    install_proxmox
    
    log_info "Waiting for installation to complete..."
    sleep 5
    
    # Boot and configure Proxmox
    boot_proxmox_with_port_forwarding || {
        log_error "Failed to boot Proxmox with port forwarding. Exiting."
        exit 1
    }
    
    # Configure Proxmox
    configure_proxmox_via_ssh
    
    # Finalize installation
    finalize_installation
}

# Execute main function
main