#!/bin/bash
#====================================================
#	VPN Manager - Ubuntu 22.04 Compatible
#	Modified for Myanmar Users
#====================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Clear screen
clear

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════╗"
    echo "║                                            ║"
    echo "║        VPN MANAGER - Myanmar Edition      ║"
    echo "║              Ubuntu 22.04                  ║"
    echo "║                                            ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Get server IP
get_ip() {
    IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || wget -qO- ipv4.icanhazip.com 2>/dev/null)
    IP2=$(curl -s whatismyip.akamai.com 2>/dev/null || wget -qO- http://whatismyip.akamai.com/ 2>/dev/null)
    [[ "$IP" != "$IP2" ]] && SERVER_IP="$IP2" || SERVER_IP="$IP"
    echo -e "$SERVER_IP" > /etc/SERVER_IP
}

# Create directories
create_directories() {
    echo -e "${YELLOW}Creating necessary directories...${NC}"
    
    directories=(
        "/etc/VPNManager"
        "/etc/VPNManager/users"
        "/etc/VPNManager/logs"
        "/etc/VPNManager/backups"
        "/etc/VPNManager/configs"
        "/etc/VPNManager/scripts"
        "/etc/VPNManager/temp"
        "/var/log/vpnmanager"
    )
    
    for dir in "${directories[@]}"; do
        [[ ! -d "$dir" ]] && mkdir -p "$dir"
    done
    
    # Create user database file
    [[ ! -e /etc/VPNManager/users/userdb ]] && touch /etc/VPNManager/users/userdb
    
    echo -e "${GREEN}Directories created successfully!${NC}"
}

# Set timezone
set_timezone() {
    echo -e "${YELLOW}Setting timezone to Asia/Yangon...${NC}"
    timedatectl set-timezone Asia/Yangon 2>/dev/null || {
        echo "Asia/Yangon" > /etc/timezone
        ln -fs /usr/share/zoneinfo/Asia/Yangon /etc/localtime
        dpkg-reconfigure --frontend noninteractive tzdata >/dev/null 2>&1
    }
    echo -e "${GREEN}Timezone set successfully!${NC}"
}

# Install dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    
    apt-get update -y
    
    packages=(
        "curl"
        "wget"
        "screen"
        "cron"
        "nano"
        "net-tools"
        "python3"
        "python3-pip"
        "jq"
        "bc"
        "apache2"
        "openssh-server"
        "ufw"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            echo -e "${CYAN}Installing $package...${NC}"
            apt-get install -y "$package" >/dev/null 2>&1
        fi
    done
    
    echo -e "${GREEN}Dependencies installed successfully!${NC}"
}

# Configure SSH
configure_ssh() {
    echo -e "${YELLOW}Configuring SSH...${NC}"
    
    # Backup original config
    [[ ! -e /etc/ssh/sshd_config.bak ]] && cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Enable SSH on port 22 if disabled
    if grep -q "^#Port 22" /etc/ssh/sshd_config; then
        sed -i "s/^#Port 22/Port 22/" /etc/ssh/sshd_config
    fi
    
    # Enable password authentication
    sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    
    # Enable root login (optional - for management purposes)
    sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    
    # Restart SSH
    systemctl restart ssh
    systemctl enable ssh
    
    echo -e "${GREEN}SSH configured successfully!${NC}"
}

# Configure Apache
configure_apache() {
    echo -e "${YELLOW}Configuring Apache...${NC}"
    
    # Change Apache port if 80 is in use
    if ss -tlnp | grep -q ':80 '; then
        sed -i "s/Listen 80/Listen 81/g" /etc/apache2/ports.conf
        echo -e "${YELLOW}Apache moved to port 81${NC}"
    fi
    
    systemctl restart apache2 2>/dev/null
    systemctl enable apache2 2>/dev/null
    
    echo -e "${GREEN}Apache configured successfully!${NC}"
}

# Download management scripts
download_scripts() {
    echo -e "${YELLOW}Downloading management scripts...${NC}"
    
    SCRIPT_DIR="/usr/local/bin"
    
    # Create main menu script
    cat > "$SCRIPT_DIR/vpnmenu" << 'MENUEOF'
#!/bin/bash
# Main VPN Manager Menu
source /etc/VPNManager/scripts/menu_functions.sh
show_main_menu
MENUEOF
    
    chmod +x "$SCRIPT_DIR/vpnmenu"
    
    # Create menu functions
    cat > /etc/VPNManager/scripts/menu_functions.sh << 'FUNCEOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

show_main_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║         VPN MANAGER - Main Menu            ║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║                                            ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[1]${NC} - User Management                     ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[2]${NC} - Connection Settings                 ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[3]${NC} - System Monitor                      ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[4]${NC} - System Tools                        ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[5]${NC} - Backup & Restore                    ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[6]${NC} - Update System                       ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[0]${NC} - Exit                                ${CYAN}║${NC}"
        echo -e "${CYAN}║                                            ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Show system info
        echo -e "${BLUE}Server IP: ${GREEN}$(cat /etc/SERVER_IP 2>/dev/null || echo 'N/A')${NC}"
        echo -e "${BLUE}Active Users: ${GREEN}$(ps aux | grep sshd | grep -v grep | wc -l)${NC}"
        echo -e "${BLUE}Uptime: ${GREEN}$(uptime -p)${NC}"
        echo ""
        
        read -p "Select an option: " option
        
        case $option in
            1) user_management_menu ;;
            2) conexao ;;
            3) system_monitor ;;
            4) system_tools_menu ;;
            5) backup_menu ;;
            6) update_system ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}" && sleep 2 ;;
        esac
    done
}

user_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          User Management Menu              ║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║                                            ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[1]${NC} - Create New User                     ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[2]${NC} - Create Test User                    ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[3]${NC} - Delete User                         ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[4]${NC} - Change Password                     ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[5]${NC} - Change Expiry Date                  ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[6]${NC} - Change Connection Limit             ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[7]${NC} - List All Users                      ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[8]${NC} - Online Users                        ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[0]${NC} - Back to Main Menu                   ${CYAN}║${NC}"
        echo -e "${CYAN}║                                            ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "Select an option: " option
        
        case $option in
            1) criarusuario ;;
            2) criarteste ;;
            3) remover ;;
            4) alterarsenha ;;
            5) mudardata ;;
            6) alterarlimite ;;
            7) infousers ;;
            8) sshmonitor ;;
            0) return ;;
            *) echo -e "${RED}Invalid option!${NC}" && sleep 2 ;;
        esac
    done
}

system_tools_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║            System Tools Menu               ║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║                                            ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[1]${NC} - Speed Test                          ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[2]${NC} - Optimize System                     ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[3]${NC} - Change Banner                       ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[4]${NC} - Change Root Password                ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[5]${NC} - Restart Services                    ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[6]${NC} - Restart System                      ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[7]${NC} - Add Swap Memory                     ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[0]${NC} - Back to Main Menu                   ${CYAN}║${NC}"
        echo -e "${CYAN}║                                            ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "Select an option: " option
        
        case $option in
            1) speedtest ;;
            2) otimizar ;;
            3) banner ;;
            4) senharoot ;;
            5) reiniciarservicos ;;
            6) reiniciarsistema ;;
            7) swapmemory ;;
            0) return ;;
            *) echo -e "${RED}Invalid option!${NC}" && sleep 2 ;;
        esac
    done
}

backup_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          Backup & Restore Menu             ║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║                                            ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[1]${NC} - Backup Users                        ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[2]${NC} - Restore Users                       ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[3]${NC} - View Backups                        ${CYAN}║${NC}"
        echo -e "${CYAN}║  ${YELLOW}[0]${NC} - Back to Main Menu                   ${CYAN}║${NC}"
        echo -e "${CYAN}║                                            ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "Select an option: " option
        
        case $option in
            1) userbackup create ;;
            2) userbackup restore ;;
            3) userbackup list ;;
            0) return ;;
            *) echo -e "${RED}Invalid option!${NC}" && sleep 2 ;;
        esac
    done
}

system_monitor() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            System Monitor                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    
    # System info
    echo -e "${YELLOW}System Information:${NC}"
    echo -e "${BLUE}OS: ${GREEN}$(lsb_release -d | cut -f2)${NC}"
    echo -e "${BLUE}Kernel: ${GREEN}$(uname -r)${NC}"
    echo -e "${BLUE}Uptime: ${GREEN}$(uptime -p)${NC}"
    echo ""
    
    # CPU
    echo -e "${YELLOW}CPU Usage:${NC}"
    top -bn1 | grep "Cpu(s)" | awk '{print "  "$1" "$2" "$3" "$4}'
    echo ""
    
    # Memory
    echo -e "${YELLOW}Memory Usage:${NC}"
    free -h | grep -E "Mem|Swap"
    echo ""
    
    # Disk
    echo -e "${YELLOW}Disk Usage:${NC}"
    df -h | grep -E "^/dev/"
    echo ""
    
    # Network
    echo -e "${YELLOW}Network Connections:${NC}"
    ss -s
    echo ""
    
    # Online users
    echo -e "${YELLOW}Online SSH Users:${NC}"
    ps aux | grep sshd | grep -v grep | grep -v "sshd:" | awk '{print "  "$1}'
    echo ""
    
    read -p "Press Enter to return to menu..."
}

update_system() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            Update System                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}Updating system...${NC}"
    apt-get update -y
    apt-get upgrade -y
    apt-get dist-upgrade -y
    apt-get autoremove -y
    apt-get autoclean -y
    
    echo ""
    echo -e "${GREEN}System updated successfully!${NC}"
    read -p "Press Enter to return to menu..."
}
FUNCEOF
    
    chmod +x /etc/VPNManager/scripts/menu_functions.sh
    
    echo -e "${GREEN}Scripts downloaded successfully!${NC}"
}

# Create user management scripts
create_user_scripts() {
    echo -e "${YELLOW}Creating user management scripts...${NC}"
    
    # Create user script
    cat > /usr/local/bin/criarusuario << 'CREATEUSEREOF'
#!/bin/bash
source /etc/VPNManager/scripts/menu_functions.sh

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            Create New User                 ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

read -p "Username: " username
if [[ -z "$username" ]]; then
    echo -e "${RED}Username cannot be empty!${NC}"
    sleep 2
    exit 1
fi

# Check if user exists
if id "$username" &>/dev/null; then
    echo -e "${RED}User already exists!${NC}"
    sleep 2
    exit 1
fi

read -p "Password: " password
if [[ -z "$password" ]]; then
    echo -e "${RED}Password cannot be empty!${NC}"
    sleep 2
    exit 1
fi

read -p "Expiry days: " days
if [[ -z "$days" ]]; then
    days=30
fi

read -p "Connection limit: " limit
if [[ -z "$limit" ]]; then
    limit=1
fi

# Create user
useradd -M -s /bin/false "$username"
echo "$username:$password" | chpasswd

# Set expiry
expiry_date=$(date -d "+$days days" +%Y-%m-%d)
chage -E $expiry_date "$username"

# Save to database
echo "$username|$password|$expiry_date|$limit|$(date +%Y-%m-%d)" >> /etc/VPNManager/users/userdb
IP9=$(wget -4qO- "http://whatismyip.akamai.com/")
echo ""
echo -e "${GREEN}User created successfully!${NC}"
echo -e "${BLUE}Username: ${GREEN}$username${NC}"
echo -e "${BLUE}Password: ${GREEN}$password${NC}"
echo -e "${BLUE}Expiry: ${GREEN}$expiry_date${NC}"
echo -e "${BLUE}Limit: ${GREEN}$limit${NC}"
echo ""
echo -e "\033[1;32mOVPN LINK\033[1;37m: \033[1;36m$IP9:81/openvpn/vpn.zip\033[0m"
read -p "Press Enter to continue..."
CREATEUSEREOF
    
    chmod +x /usr/local/bin/criarusuario
    
    # Delete user script
    cat > /usr/local/bin/remover << 'DELETEUSEREOF'
#!/bin/bash
source /etc/VPNManager/scripts/menu_functions.sh

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            Delete User                     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

read -p "Username to delete: " username
if [[ -z "$username" ]]; then
    echo -e "${RED}Username cannot be empty!${NC}"
    sleep 2
    exit 1
fi

if ! id "$username" &>/dev/null; then
    echo -e "${RED}User does not exist!${NC}"
    sleep 2
    exit 1
fi

# Kill user sessions
pkill -u "$username" 2>/dev/null

# Delete user
userdel -r "$username" 2>/dev/null

# Remove from database
sed -i "/^$username|/d" /etc/VPNManager/users/userdb

echo ""
echo -e "${GREEN}User deleted successfully!${NC}"
read -p "Press Enter to continue..."
DELETEUSEREOF
    
    chmod +x /usr/local/bin/remover
    
    # List users script
    cat > /usr/local/bin/infousers << 'LISTUSERSEOF'
#!/bin/bash
source /etc/VPNManager/scripts/menu_functions.sh

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            All Users List                  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

if [[ ! -s /etc/VPNManager/users/userdb ]]; then
    echo -e "${YELLOW}No users found!${NC}"
else
    echo -e "${BLUE}Username${NC}  ${BLUE}Expiry${NC}      ${BLUE}Limit${NC}  ${BLUE}Created${NC}"
    echo "────────────────────────────────────────────────"
    
    while IFS='|' read -r user pass expiry limit created; do
        echo -e "${GREEN}$user${NC}     $expiry    $limit      $created"
    done < /etc/VPNManager/users/userdb
fi

echo ""
read -p "Press Enter to continue..."
LISTUSERSEOF
    
    chmod +x /usr/local/bin/infousers
    
    # Monitor online users
    cat > /usr/local/bin/sshmonitor << 'MONITOREOF'
#!/bin/bash
source /etc/VPNManager/scripts/menu_functions.sh

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            Online Users                    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

online_users=$(ps aux | grep sshd | grep -v grep | grep -v "sshd:" | awk '{print $1}' | sort | uniq)

if [[ -z "$online_users" ]]; then
    echo -e "${YELLOW}No users online!${NC}"
else
    echo -e "${BLUE}Username${NC}    ${BLUE}Connections${NC}  ${BLUE}Time${NC}"
    echo "────────────────────────────────────────────────"
    
    for user in $online_users; do
        connections=$(ps aux | grep "$user" | grep sshd | grep -v grep | wc -l)
        echo -e "${GREEN}$user${NC}           $connections"
    done
fi

echo ""
read -p "Press Enter to continue..."
MONITOREOF
    
    chmod +x /usr/local/bin/sshmonitor
    
    echo -e "${GREEN}User management scripts created!${NC}"
}

# Create system tools scripts
create_system_scripts() {
    echo -e "${YELLOW}Creating system tools scripts...${NC}"
    
    # Speed test
    cat > /usr/local/bin/speedtest << 'SPEEDEOF'
#!/bin/bash
source /etc/VPNManager/scripts/menu_functions.sh

clear
echo -e "${CYAN}Running speed test...${NC}"
echo ""

if ! command -v speedtest-cli &> /dev/null; then
    echo -e "${YELLOW}Installing speedtest-cli...${NC}"
    pip3 install speedtest-cli
fi

speedtest-cli

echo ""
read -p "Press Enter to continue..."
SPEEDEOF
    
    chmod +x /usr/local/bin/speedtest
    
    # Other utility scripts
    for script in "otimizar" "banner" "senharoot" "reiniciarservicos" "reiniciarsistema" "alterarsenha" "mudardata" "alterarlimite" "criarteste" "userbackup" "swapmemory"; do
        cat > /usr/local/bin/$script << 'EOF'
#!/bin/bash
echo "This feature is under development"
sleep 2
EOF
        chmod +x /usr/local/bin/$script
    done
    
    echo -e "${GREEN}System tools scripts created!${NC}"
}

# Setup cron jobs
setup_cron() {
    echo -e "${YELLOW}Setting up cron jobs...${NC}"
    
    # Remove existing cron jobs
    crontab -r 2>/dev/null
    
    # Add new cron jobs
    (
        crontab -l 2>/dev/null
        echo "0 0 * * * /usr/local/bin/expcleaner"
        echo "@reboot /etc/VPNManager/scripts/autostart.sh"
    ) | crontab -
    
    # Create autostart script
    cat > /etc/VPNManager/scripts/autostart.sh << 'AUTOEOF'
#!/bin/bash
# Auto-start services
AUTOEOF
    
    chmod +x /etc/VPNManager/scripts/autostart.sh
    
    # Restart cron
    systemctl restart cron
    
    echo -e "${GREEN}Cron jobs setup complete!${NC}"
}

# Create user cleaner
create_cleaner() {
    cat > /usr/local/bin/expcleaner << 'CLEANEOF'
#!/bin/bash
# Clean expired users

today=$(date +%Y-%m-%d)

while IFS='|' read -r user pass expiry limit created; do
    if [[ "$expiry" < "$today" ]]; then
        pkill -u "$user" 2>/dev/null
        userdel -r "$user" 2>/dev/null
        sed -i "/^$user|/d" /etc/VPNManager/users/userdb
        echo "Deleted expired user: $user"
    fi
done < /etc/VPNManager/users/userdb
CLEANEOF
    
    chmod +x /usr/local/bin/expcleaner
}

# Final setup
final_setup() {
    echo -e "${YELLOW}Performing final setup...${NC}"
    
    # Create version file
    echo "1.0.0" > /etc/VPNManager/version
    
    # Create command alias
    echo 'alias vpn="vpnmenu"' >> ~/.bashrc
    echo 'alias menu="vpnmenu"' >> ~/.bashrc
    
    # Create desktop shortcut (if GUI exists)
    if [[ -d /usr/share/applications ]]; then
        cat > /usr/share/applications/vpnmanager.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=VPN Manager
Comment=VPN Management System
Exec=x-terminal-emulator -e vpnmenu
Icon=network-server
Terminal=true
Type=Application
Categories=System;Network;
DESKTOPEOF
    fi
    
    echo -e "${GREEN}Final setup complete!${NC}"
}

# Main installation
main_install() {
    show_banner
    echo -e "${YELLOW}Starting VPN Manager installation...${NC}"
    echo ""
    
    get_ip
    create_directories
    set_timezone
    install_dependencies
    configure_ssh
    configure_apache
    download_scripts
    create_user_scripts
    create_system_scripts
    create_cleaner
    setup_cron
    final_setup
    
    clear
    show_banner
    echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                            ║${NC}"
    echo -e "${GREEN}║   Installation completed successfully!     ║${NC}"
    echo -e "${GREEN}║                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}To start the VPN Manager, run:${NC}"
    echo -e "${YELLOW}  vpnmenu${NC}"
    echo -e "${CYAN}or simply:${NC}"
    echo -e "${YELLOW}  menu${NC}"
    echo ""
    echo -e "${BLUE}Server IP: ${GREEN}$SERVER_IP${NC}"
    echo ""
    read -p "Press Enter to start VPN Manager..."
    
    vpnmenu
}

# Run installation
main_install
