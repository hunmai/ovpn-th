#!/bin/bash

CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="$CONFIG_DIR/config.json"
USER_DB="$CONFIG_DIR/users.db"
SYSTEMD_SERVICE="/etc/systemd/system/hysteria-server.service"
WEB_DIR="/var/www/html/udpserver"
WEB_STATUS_FILE="$WEB_DIR/online"
WEB_APP_FILE="$WEB_DIR/online_app"
WEB_SYSTEM_FILE="$WEB_DIR/system_info"
CRON_FILE="/etc/cron.d/hysteria_user_expiry"
DEFAULT_LIMIT="2500"

# Create directories and files
mkdir -p "$CONFIG_DIR"
mkdir -p "/var/log/hysteria"
mkdir -p "$WEB_DIR"
touch "$USER_DB"

# Ensure web files exist with proper permissions
if [[ ! -f "$WEB_APP_FILE" ]]; then
    echo "{\"onlines\":\"0\",\"limite\":\"$DEFAULT_LIMIT\"}" > "$WEB_APP_FILE"
fi
if [[ ! -f "$WEB_STATUS_FILE" ]]; then
    echo "0" > "$WEB_STATUS_FILE"
fi
chmod 666 "$WEB_STATUS_FILE" "$WEB_APP_FILE" 2>/dev/null

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Check for root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    exit 1
fi

# Get IPv4 address only
get_ipv4() {
    local ip=$(curl -4 -s --connect-timeout 3 ifconfig.me 2>/dev/null)
    if [[ -z "$ip" ]] || [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    fi
    echo "$ip"
}

# Check if web server is enabled
is_web_enabled() {
    if [[ -f "/etc/nginx/sites-enabled/udp-status" ]] && systemctl is-active nginx >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get domain from config
get_domain() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local domain=$(jq -r '.listen // empty' "$CONFIG_FILE" 2>/dev/null | cut -d':' -f1)
        if [[ -z "$domain" ]]; then
            domain=$(get_ipv4)
        fi
        echo "$domain"
    else
        echo $(get_ipv4)
    fi
}

# Get obfuscation from config
get_obfuscation() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local obfs=$(jq -r '.obfs // empty' "$CONFIG_FILE" 2>/dev/null)
        if [[ -z "$obfs" ]] || [[ "$obfs" == "null" ]]; then
            echo "None"
        else
            echo "$obfs"
        fi
    else
        echo "None"
    fi
}

# Update system info file for web dashboard
update_system_info() {
    local server_ip=$(get_ipv4)
    local domain=$(get_domain)
    local obfs=$(get_obfuscation)
    local online_count=$(cat "$WEB_STATUS_FILE" 2>/dev/null || echo "0")
    local cpu_cores=$(nproc)
    
    # === CPU USAGE FIX (REPLACED top WITH vmstat) ===
    # Using vmstat is much lighter than top -bn1
    local cpu_usage=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
    
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")
    
    local hysteria_status="offline"
    if systemctl is-active hysteria-server >/dev/null 2>&1; then
        hysteria_status="online"
    fi
    
    local web_status="off"
    if is_web_enabled; then
        web_status="on"
    fi
    
    cat > "$WEB_SYSTEM_FILE" << EOF
{
    "server_ip": "$server_ip",
    "domain": "$domain",
    "obfuscation": "$obfs",
    "online": "$online_count",
    "cpu_cores": "$cpu_cores",
    "cpu_usage": "$cpu_usage",
    "mem_total": "$mem_total",
    "mem_used": "$mem_used",
    "mem_percent": "$mem_percent",
    "hysteria_status": "$hysteria_status",
    "web_status": "$web_status"
}
EOF
    chmod 666 "$WEB_SYSTEM_FILE" 2>/dev/null
}

# Install dependencies if not installed
install_dependencies() {
    local installed_all=true

echo -e "${BLUE}Configuring systemd-journald for persistent logs...${NC}"
# Create journal directory if not exists
    if [[ ! -d "/var/log/journal" ]]; then
        mkdir -p /var/log/journal
        systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true
        echo -e "${GREEN}✓ Created /var/log/journal${NC}"
    else
        echo -e "${GREEN}✓ /var/log/journal already exists${NC}"
    fi
    
    # Enable persistent storage in journald
    if ! grep -q "^Storage=persistent" /etc/systemd/journald.conf 2>/dev/null; then
        sed -i 's/^#Storage=auto/Storage=persistent/' /etc/systemd/journald.conf 2>/dev/null
        sed -i 's/^Storage=auto/Storage=persistent/' /etc/systemd/journald.conf 2>/dev/null
        
        # If no Storage line exists, add it
        if ! grep -q "^Storage=" /etc/systemd/journald.conf 2>/dev/null; then
            sed -i '/\[Journal\]/a Storage=persistent' /etc/systemd/journald.conf 2>/dev/null
        fi
        
        systemctl restart systemd-journald
        echo -e "${GREEN}✓ journald configured for persistent logging${NC}"
    else
        echo -e "${GREEN}✓ journald already configured${NC}"
    fi
    
    # Check for vmstat (procps)
    if ! command -v vmstat &> /dev/null; then
        echo -e "${YELLOW}Installing procps (for vmstat)...${NC}"
        apt-get update -y
        apt-get install -y procps
        if ! command -v vmstat &> /dev/null; then
             echo -e "${RED}✗ procps installation failed${NC}"
             installed_all=false
        else
             echo -e "${GREEN}✓ procps installed${NC}"
        fi
    else
        echo -e "${GREEN}✓ procps (vmstat) already installed${NC}"
    fi

    if ! command -v redis-cli &> /dev/null; then
        echo -e "${YELLOW}Installing Redis...${NC}"
        apt-get update -y
        apt-get install -y redis-server
        
        sed -i 's/^# maxmemory <bytes>/maxmemory 256mb/' /etc/redis/redis.conf 2>/dev/null || true
        sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf 2>/dev/null || true
        
        systemctl enable redis-server
        systemctl restart redis-server
        sleep 2
        
        if systemctl is-active redis-server >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Redis installed and running${NC}"
        else
            echo -e "${RED}✗ Redis installation failed${NC}"
            installed_all=false
        fi
    else
        echo -e "${GREEN}✓ Redis already installed${NC}"
    fi
    
    if ! command -v sqlite3 &> /dev/null; then
        echo -e "${YELLOW}Installing SQLite3...${NC}"
        apt-get install -y sqlite3
        if ! command -v sqlite3 &> /dev/null; then
             echo -e "${RED}✗ SQLite3 installation failed${NC}"
             installed_all=false
        else
             echo -e "${GREEN}✓ SQLite3 installed${NC}"
        fi
    else
        echo -e "${GREEN}✓ SQLite3 already installed${NC}"
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Installing jq...${NC}"
        apt-get install -y jq
        if ! command -v jq &> /dev/null; then
             echo -e "${RED}✗ jq installation failed${NC}"
             installed_all=false
        else
             echo -e "${GREEN}✓ jq installed${NC}"
        fi
    else
        echo -e "${GREEN}✓ jq already installed${NC}"
    fi
    
    if ! $installed_all; then
        echo -e "${RED}Failed to install one or more dependencies. Please install them manually.${NC}"
        exit 1
    fi
}

# Initialize database
init_database() {
    sqlite3 "$USER_DB" "CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        username TEXT UNIQUE NOT NULL, 
        password TEXT NOT NULL,
        expire_date INTEGER DEFAULT 0 NOT NULL
    );"
    
    sqlite3 "$USER_DB" "ALTER TABLE users ADD COLUMN expire_date INTEGER DEFAULT 0 NOT NULL" 2>/dev/null || true
    sqlite3 "$USER_DB" "PRAGMA journal_mode=WAL;" >/dev/null 2>&1
}

# Fetch ONLY non-expired users
fetch_users() {
    local now_ts=$(date +%s)
    if [[ -f "$USER_DB" ]]; then
        sqlite3 "$USER_DB" "SELECT username || ':' || password FROM users WHERE expire_date = 0 OR expire_date > $now_ts;" | paste -sd, -
    fi
}

# Update Hysteria config.json
update_userpass_config() {
    echo -e "${BLUE}Updating Hysteria config with active users...${NC}"
    local users=$(fetch_users)
    local user_array
    
    if [[ -z "$users" ]]; then
        user_array="[]"
    else
        user_array="[$(echo "$users" | awk -F, '{for(i=1;i<=NF;i++) printf "\"" $i "\"" ((i==NF) ? "" : ",")}')]"
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}Config file $CONFIG_FILE not found!${NC}"
        return 1
    fi
    
    jq ".auth.config = $user_array" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Config updated successfully.${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to update config.${NC}"
        return 1
    fi
}

# Setup cron job
setup_user_expiry_cron() {
    local SCRIPT_PATH
    SCRIPT_PATH="/usr/local/bin/udp" # Use the final installed path
    
    echo -e "${BLUE}Setting up hourly cron job for user expiry check...${NC}"
    echo "0 * * * * root $SCRIPT_PATH updateconfig" > "$CRON_FILE"
    chmod 0644 "$CRON_FILE"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Cron job created successfully.${NC}"
    else
        echo -e "${RED}✗ Failed to create cron job.${NC}"
    fi
}

# Setup online monitor service
setup_online_monitor_service() {
    echo -e "${BLUE}Setting up online-monitor service (Optimized)...${NC}"
    
    cat > /etc/systemd/system/hysteria-online-monitor.service << 'EOF'
[Unit]
Description=Hysteria Online Users Monitor (Redis - Ultra-Fast HLEN)
After=redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria-online-monitor.sh
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /usr/local/bin/hysteria-online-monitor.sh << 'MONITOREOF'
#!/bin/bash

WEB_DIR="/var/www/html/udpserver"
WEB_STATUS_FILE="$WEB_DIR/online"
WEB_APP_FILE="$WEB_DIR/online_app"
WEB_SYSTEM_FILE="$WEB_DIR/system_info"
CONFIG_FILE="/etc/hysteria/config.json"
DEFAULT_LIMIT="2500"

echo "Starting Online Users Monitor (Redis - Ultra-Fast HLEN)"
echo "Update interval: 3 seconds"

mkdir -p "$WEB_DIR"
chmod 777 "$WEB_DIR" 2>/dev/null
iteration=0

# Function to get IPv4
get_ipv4() {
    local ip=$(curl -4 -s --connect-timeout 3 ifconfig.me 2>/dev/null)
    if [[ -z "$ip" ]] || [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    fi
    echo "$ip"
}

# Function to check if web is enabled
is_web_enabled() {
    if [[ -f "/etc/nginx/sites-enabled/udp-status" ]] && systemctl is-active nginx >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Ensure vmstat is available
if ! command -v vmstat &> /dev/null; then
    echo "Error: vmstat not found. Please install procps."
    exit 1
fi

while true; do
    iteration=$((iteration + 1))
    
    _onli=$(redis-cli HLEN udp:ip_last_seen 2>/dev/null)
    
    if ! [[ "$_onli" =~ ^[0-9]+$ ]]; then
        _onli=0
    fi
    
    current_limit=$(grep -oP '"limite":"\K[0-9]+(?=")' "$WEB_APP_FILE" 2>/dev/null || echo "$DEFAULT_LIMIT")
    
    echo "$_onli" > "${WEB_STATUS_FILE}.tmp" 2>/dev/null && mv "${WEB_STATUS_FILE}.tmp" "$WEB_STATUS_FILE"
    echo "{\"onlines\":\"$_onli\",\"limite\":\"$current_limit\"}" > "${WEB_APP_FILE}.tmp" 2>/dev/null && mv "${WEB_APP_FILE}.tmp" "$WEB_APP_FILE"
    chmod 666 "$WEB_STATUS_FILE" "$WEB_APP_FILE" 2>/dev/null
    
    # Update system info every iteration
    server_ip=$(get_ipv4)
    domain=$(jq -r '.listen // empty' "$CONFIG_FILE" 2>/dev/null | cut -d':' -f1)
    [[ -z "$domain" ]] && domain="$server_ip"
    obfs=$(jq -r '.obfs // empty' "$CONFIG_FILE" 2>/dev/null)
    [[ -z "$obfs" ]] || [[ "$obfs" == "null" ]] && obfs="None"
    
    cpu_cores=$(nproc)
    
    # === CPU USAGE FIX (REPLACED top WITH vmstat) ===
    # Using vmstat is much lighter than top -bn1
    cpu_usage=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
    
    mem_total=$(free -m | awk 'NR==2{print $2}')
    mem_used=$(free -m | awk 'NR==2{print $3}')
    mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")
    
    hysteria_status="offline"
    systemctl is-active hysteria-server >/dev/null 2>&1 && hysteria_status="online"
    
    web_status="off"
    is_web_enabled && web_status="on"
    
    cat > "${WEB_SYSTEM_FILE}.tmp" << SYSEOF
{
    "server_ip": "$server_ip",
    "domain": "$domain",
    "obfuscation": "$obfs",
    "online": "$_onli",
    "cpu_cores": "$cpu_cores",
    "cpu_usage": "$cpu_usage",
    "mem_total": "$mem_total",
    "mem_used": "$mem_used",
    "mem_percent": "$mem_percent",
    "hysteria_status": "$hysteria_status",
    "web_status": "$web_status"
}
SYSEOF
    mv "${WEB_SYSTEM_FILE}.tmp" "$WEB_SYSTEM_FILE" 2>/dev/null
    chmod 666 "$WEB_SYSTEM_FILE" 2>/dev/null
    
    sleep 3
done
MONITOREOF

    chmod +x /usr/local/bin/hysteria-online-monitor.sh
    systemctl daemon-reload
    systemctl enable hysteria-online-monitor
    
    echo -e "${GREEN}✓ Online-monitor service created (Optimized)${NC}"
}

# Setup tracker service
setup_tracker_service() {
    echo -e "${BLUE}Setting up hysteria-tracker service (Optimized)...${NC}"
    
    cat > /etc/systemd/system/hysteria-tracker.service << 'EOF'
[Unit]
Description=Hysteria Connection Tracker (Redis - Ultra-Fast Lua)
After=redis-server.service hysteria-server.service
Requires=redis-server.service hysteria-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria-tracker.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /usr/local/bin/hysteria-tracker.sh << 'TRACKEREOF'
#!/bin/bash

echo "╔══════════════════════════════════════════════╗"
echo "║  Hysteria Connection Tracker - LUA OPTIMIZED ║"
echo "╚══════════════════════════════════════════════╝"
echo "⚡ Mode: Ultra-Fast (Lua Cleanup)"
echo "⚡ Update interval: 3 seconds"
echo "⚡ Cleanup interval: 3 seconds"
echo "⚡ Timeout: 15 seconds"
echo "⚡ Connect detection: 3-6s | Disconnect detection: 15-18s"

LUA_SCRIPT="
    local hash_key = KEYS[1]
    local cutoff_time = ARGV[1]
    local cursor = '0'
    local removed_count = 0
    
    repeat
        local result = redis.call('HSCAN', hash_key, cursor, 'COUNT', 500)
        cursor = result[1]
        local fields = result[2]
        
        for i = 1, #fields, 2 do
            local ip = fields[i]
            local timestamp = tonumber(fields[i+1])
            
            if timestamp and timestamp < tonumber(cutoff_time) then
                redis.call('HDEL', hash_key, ip)
                removed_count = removed_count + 1
            end
        end
    until cursor == '0'
    
    return removed_count
"

redis-cli FLUSHDB >/dev/null 2>&1
echo "✓ Cleared old sessions"

(
    while true; do
        sleep 3
        now=$(date +%s)
        cutoff=$((now - 15))
        
        removed=$(redis-cli EVAL "$LUA_SCRIPT" 1 udp:ip_last_seen "$cutoff" 2>/dev/null)
        
        if [[ "$removed" =~ ^[0-9]+$ ]] && [[ $removed -gt 0 ]]; then
            current_count=$(redis-cli HLEN udp:ip_last_seen 2>/dev/null)
            echo "[$(date '+%H:%M:%S')] 🔄 CLEANUP: Removed $removed expired IP(s) | Current online: $current_count"
        fi
    done
) &
cleanup_pid=$!

cleanup() {
    echo "Shutting down tracker..."
    kill $cleanup_pid 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

echo "🚀 Tracker started - Monitoring connections..."
declare -A LAST_UPDATE

journalctl -u hysteria-server -f -n 0 --no-pager 2>/dev/null | while read -r line; do
    ip=$(grep -oP '\[src:\K[0-9.]+(?=:)' <<< "$line")
    [[ -z "$ip" ]] && continue
    
    now=$(date +%s)
    
    if [[ -z "${LAST_UPDATE[$ip]}" ]] || [[ $((now - LAST_UPDATE[$ip])) -ge 3 ]]; then
        LAST_UPDATE[$ip]=$now
        redis-cli HSET udp:ip_last_seen "$ip" "$now" >/dev/null 2>&1
    fi
done

kill $cleanup_pid 2>/dev/null
TRACKEREOF

    chmod +x /usr/local/bin/hysteria-tracker.sh
    systemctl daemon-reload
    systemctl enable hysteria-tracker
    
    echo -e "${GREEN}✓ Hysteria-tracker service created (Optimized)${NC}"
}

start_online_monitor() {
    echo -e "${BLUE}Starting online monitor...${NC}"
    if [[ ! -f "/etc/systemd/system/hysteria-online-monitor.service" ]]; then
        setup_online_monitor_service
    fi
    systemctl restart hysteria-online-monitor
    sleep 1
    if systemctl is-active hysteria-online-monitor >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Online monitor started${NC}"
    else
        echo -e "${RED}✗ Failed to start${NC}"
    fi
}

stop_online_monitor() {
    systemctl stop hysteria-online-monitor
    echo -e "${GREEN}✓ Online monitor stopped${NC}"
}

start_connection_tracker() {
    echo -e "${BLUE}Starting connection tracker...${NC}"
    if [[ ! -f "/etc/systemd/system/hysteria-tracker.service" ]]; then
        setup_tracker_service
    fi
    systemctl restart hysteria-tracker
    sleep 1
    if systemctl is-active hysteria-tracker >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Connection tracker started${NC}"
    else
        echo -e "${RED}✗ Failed to start${NC}"
    fi
}

stop_connection_tracker() {
    systemctl stop hysteria-tracker
    echo -e "${GREEN}✓ Connection tracker stopped${NC}"
}

check_monitor_status() {
    echo -e "\n${BLUE}═══ Monitoring Status (Optimized) ═══${NC}"
    
    if systemctl is-active redis-server >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Redis is RUNNING${NC}"
    else
        echo -e "${RED}✗ Redis is NOT RUNNING${NC}"
    fi
    
    if systemctl is-active hysteria-online-monitor >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Online Monitor (HLEN) is RUNNING${NC}"
    else
        echo -e "${RED}✗ Online Monitor is NOT RUNNING${NC}"
    fi
    
    if systemctl is-active hysteria-tracker >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Connection Tracker (Lua) is RUNNING${NC}"
    else
        echo -e "${RED}✗ Connection Tracker is NOT RUNNING${NC}"
    fi
    
    if systemctl is-active hysteria-server >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Hysteria Server is RUNNING${NC}"
    else
        echo -e "${RED}✗ Hysteria Server is NOT RUNNING${NC}"
    fi
    
    if systemctl is-active nginx >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Nginx is RUNNING${NC}"
    else
        echo -e "${YELLOW}⚠ Nginx is not running${NC}"
    fi
    
    echo -e "\n${BLUE}═══ User Count Status ═══${NC}"
    local redis_count=$(redis-cli HLEN udp:ip_last_seen 2>/dev/null || echo "0")
    echo -e "${CYAN}Redis Tracked IPs: ${GREEN}$redis_count${NC}"
    
    local web_count=$(cat "$WEB_STATUS_FILE" 2>/dev/null || echo "0")
    echo -e "${CYAN}Web File Count:    ${GREEN}$web_count${NC}"
    
    local diff=$((redis_count - web_count))
    diff=${diff#-}
    if [[ $diff -le 1 ]]; then
        echo -e "${GREEN}✓ Counts are synchronized${NC}"
    else
        echo -e "${YELLOW}⚠ Counts are syncing (diff: $diff)${NC}"
    fi

    echo -e "\n${BLUE}═══ Performance ═══${NC}"
    echo -e "${CYAN}Connect detection: ~3-6 seconds${NC}"
    echo -e "${CYAN}Disconnect detection: ~15-18 seconds${NC}"
}

show_online_users() {
    echo -e "\n${BLUE}═══ Online Users (Redis - Live) ═══${NC}"
    
    local online_count=$(redis-cli HLEN udp:ip_last_seen 2>/dev/null || echo "0")
    echo -e "${CYAN}Total online: ${GREEN}$online_count${NC}"
    echo -e "${CYAN}Timeout: 15 seconds${NC}\n"
    
    if [[ $online_count -gt 0 ]]; then
        echo -e "${GREEN}IP Address${NC}\t\t${GREEN}Last Seen${NC}\t\t\t${GREEN}Idle Time${NC}"
        echo "─────────────────────────────────────────────────────────────────"
        
        local now=$(date +%s)
        
        redis-cli HGETALL udp:ip_last_seen 2>/dev/null | while read ip; do
            read timestamp
            
            if [[ -n "$timestamp" ]]; then
                local last_seen_fmt=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
                local idle=$(( now - timestamp ))
                local idle_sec="${idle}s ago"
                
                if [[ $idle -lt 5 ]]; then
                    printf "%-15s\t%-25s\t${GREEN}%s${NC}\n" "$ip" "$last_seen_fmt" "$idle_sec"
                elif [[ $idle -lt 10 ]]; then
                    printf "%-15s\t%-25s\t${YELLOW}%s${NC}\n" "$ip" "$last_seen_fmt" "$idle_sec"
                else
                    printf "%-15s\t%-25s\t${RED}%s${NC}\n" "$ip" "$last_seen_fmt" "$idle_sec"
                fi
            fi
        done | sort -k3 -n
    else
        echo -e "${YELLOW}No users currently online${NC}"
    fi
}

show_redis_stats() {
    echo -e "\n${BLUE}═══ Redis Statistics ═══${NC}"
    echo -e "${CYAN}Memory:${NC}"
    redis-cli INFO memory 2>/dev/null | grep -E "used_memory_human|used_memory_peak_human" | sed 's/^/  /'
    
    echo -e "\n${CYAN}Stats:${NC}"
    redis-cli INFO stats 2>/dev/null | grep -E "total_connections_received|total_commands_processed|instantaneous_ops_per_sec" | sed 's/^/  /'
    
    echo -e "\n${CYAN}Tracked Data:${NC}"
    echo "  Tracked IPs: $(redis-cli HLEN udp:ip_last_seen 2>/dev/null)"
    
    echo -e "\n${CYAN}Performance:${NC}"
    echo "  Cleanup Mode: Lua (Ultra-Fast)"
    echo "  Monitor Mode: HLEN (Ultra-Fast)"
    echo "  Timeout: 15 seconds"
}

clear_redis_data() {
    echo -e "\n${YELLOW}Clear all Redis session data (FLUSHDB)? (yes/no):${NC}"
    read -r confirm
    
    if [[ "$confirm" == "yes" ]]; then
        redis-cli FLUSHDB >/dev/null 2>&1
        echo "0" > "$WEB_STATUS_FILE"
        local current_limit=$(grep -oP '"limite":"\K[0-9]+(?=")' "$WEB_APP_FILE" 2>/dev/null || echo "$DEFAULT_LIMIT")
        echo "{\"onlines\":\"0\",\"limite\":\"$current_limit\"}" > "$WEB_APP_FILE"
        chmod 666 "$WEB_STATUS_FILE" "$WEB_APP_FILE" 2>/dev/null
        echo -e "${GREEN}✓ All session data cleared${NC}"
    else
        echo -e "${YELLOW}Cancelled${NC}"
    fi
}

# =================================================================
# === ဒီ Function တစ်ခုလုံးကို အသစ်ပြင်ဆင်ထားပါသည် ===
# =================================================================
# Toggle web server ON/OFF
toggle_web_server() {
    if is_web_enabled; then
        echo -e "\n${YELLOW}Web server is currently: ${GREEN}ON${NC}"
        echo -e "${BLUE}Do you want to turn it OFF? (yes/no):${NC}"
        read -r confirm
        
        if [[ "$confirm" == "yes" ]]; then
            rm -f /etc/nginx/sites-enabled/udp-status
            
            # === (FIX) ===
            # Web server ကို ပိတ်လိုက်တဲ့အခါ 'default' config ကို ပြန်ဖွင့်ပေးပါမယ်။
            if [[ -f "/etc/nginx/sites-available/default" ]]; then
                 ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
            fi
            # === (END OF FIX) ===
            
            systemctl reload nginx 2>/dev/null
            echo -e "${GREEN}✓ Web server turned OFF${NC}"
        else
            echo -e "${YELLOW}Cancelled${NC}"
        fi
    else
        echo -e "\n${YELLOW}Web server is currently: ${RED}OFF${NC}"
        echo -e "${BLUE}Do you want to turn it ON? (yes/no):${NC}"
        read -r confirm
        
        if [[ "$confirm" == "yes" ]]; then
            if ! command -v nginx &> /dev/null; then
                echo -e "${YELLOW}Installing nginx...${NC}"
                apt-get update -y && apt-get install -y nginx
                systemctl start nginx
                systemctl enable nginx
            fi
            
            mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
            
            if ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
                sed -i '/include \/etc\/nginx\/conf.d\/\*.conf;/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
            fi
            
            # Nginx config with proper headers for inline viewing (NO DOWNLOAD)
            cat > /etc/nginx/sites-available/udp-status << 'NGINXEOF'
server {
    listen 80;
    server_name _;
    root /var/www/html;
    
    location /udpserver/ {
        autoindex on;
        add_header Access-Control-Allow-Origin *;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }
    
    location = /udpserver/online {
        default_type "text/plain; charset=utf-8";
        add_header Access-Control-Allow-Origin *;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header X-Content-Type-Options "nosniff";
        add_header Content-Disposition "inline"; # API အဖြစ်ပြရန် (ဒေါင်းလုဒ်မလုပ်စေရန်)
    }
    
    location = /udpserver/online_app {
        default_type "application/json; charset=utf-8";
        add_header Access-Control-Allow-Origin *;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header X-Content-Type-Options "nosniff";
        add_header Content-Disposition "inline"; # API အဖြစ်ပြရန် (ဒေါင်းလုဒ်မလုပ်စေရန်)
    }
    
    location = /udpserver/system_info {
        default_type "application/json; charset=utf-8";
        add_header Access-Control-Allow-Origin *;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header X-Content-Type-Options "nosniff";
        add_header Content-Disposition "inline"; # API အဖြစ်ပြရန် (ဒေါင်းလုဒ်မလုပ်စေရန်)
    }
}
NGINXEOF

            ln -sf /etc/nginx/sites-available/udp-status /etc/nginx/sites-enabled/udp-status
            
            # === (FIX) Nginx Conflict ===
            # Nginx config လုနေတဲ့ 'default' file ကို အလိုအလျောက် ဖြုတ်ပေးပါမယ်။
            rm -f /etc/nginx/sites-enabled/default
            # === (END OF FIX) ===
            
            # Simple dashboard with copy link buttons only
            cat > "$WEB_DIR/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hysteria UDP Manager</title>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500;700&display=swap" rel="stylesheet">
    <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Roboto', -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .app-bar {
            background: rgba(255, 255, 255, 0.98);
            color: #333;
            padding: 32px;
            border-radius: 16px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.15);
            margin-bottom: 24px;
            text-align: center;
        }
        
        .app-bar h1 {
            font-size: 36px;
            font-weight: 700;
            margin-bottom: 12px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        .app-bar .subtitle {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            color: #666;
            font-size: 15px;
        }
        
        .pulse-dot {
            width: 10px;
            height: 10px;
            background: #4caf50;
            border-radius: 50%;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.6; transform: scale(1.2); }
        }
        
        .card {
            background: rgba(255, 255, 255, 0.98);
            border-radius: 16px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.15);
            padding: 32px;
            margin-bottom: 24px;
            transition: all 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-4px);
            box-shadow: 0 12px 48px rgba(0,0,0,0.2);
        }
        
        .card-title {
            font-size: 15px;
            font-weight: 600;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            margin-bottom: 24px;
            display: flex;
            align-items: center;
            gap: 10px;
            padding-bottom: 16px;
            border-bottom: 2px solid #f0f0f0;
        }
        
        .card-title .material-icons {
            font-size: 24px;
            color: #667eea;
        }
        
        .online-hero {
            text-align: center;
            padding: 48px 20px;
            background: linear-gradient(135deg, #667eea15 0%, #764ba215 100%);
            border-radius: 12px;
        }
        
        .online-count {
            font-size: 120px;
            font-weight: 300;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            line-height: 1;
            margin: 24px 0;
        }
        
        .online-label {
            font-size: 20px;
            color: #666;
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 2px;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }
        
        .info-item {
            background: linear-gradient(135deg, #667eea15 0%, #764ba215 100%);
            padding: 20px;
            border-radius: 12px;
            text-align: center;
        }
        
        .info-label {
            font-size: 12px;
            color: #999;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 8px;
        }
        
        .info-value {
            font-size: 18px;
            color: #333;
            font-weight: 600;
            word-break: break-all;
        }
        
        .api-links {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        
        .api-link-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 12px;
            padding: 28px;
            color: white;
            transition: all 0.3s ease;
        }
        
        .api-link-card:hover {
            transform: translateY(-4px);
            box-shadow: 0 12px 32px rgba(102, 126, 234, 0.4);
        }
        
        .api-link-header {
            display: flex;
            align-items: center;
            gap: 12px;
            margin-bottom: 16px;
        }
        
        .api-link-header .material-icons {
            font-size: 32px;
        }
        
        .api-link-title {
            font-size: 20px;
            font-weight: 600;
            letter-spacing: 1px;
        }
        
        .api-url-box {
            background: rgba(255, 255, 255, 0.2);
            padding: 14px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            word-break: break-all;
            margin-bottom: 16px;
            border: 1px solid rgba(255, 255, 0.3);
        }
        
        .api-buttons {
            display: flex;
            gap: 12px;
        }
        
        .btn {
            flex: 1;
            background: rgba(255, 255, 255, 0.95);
            color: #667eea;
            border: none;
            padding: 14px 20px;
            border-radius: 8px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            font-size: 14px;
            font-weight: 600;
            transition: all 0.2s ease;
            text-decoration: none;
        }
        
        .btn:hover {
            background: white;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.2);
        }
        
        .btn:active {
            transform: translateY(0);
        }
        
        .btn .material-icons {
            font-size: 20px;
        }
        
        .btn.copied {
            background: #4caf50;
            color: white;
        }
        
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 16px;
        }
        
        .status-item {
            background: linear-gradient(135deg, #667eea15 0%, #764ba215 100%);
            border-radius: 12px;
            padding: 24px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .status-label {
            font-size: 15px;
            color: #666;
            font-weight: 500;
        }
        
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .status-badge.online {
            background: #c8e6c9;
            color: #2e7d32;
        }
        
        .status-badge.offline {
            background: #ffcdd2;
            color: #c62828;
        }
        
        .status-badge .material-icons {
            font-size: 18px;
        }
        
        .metric-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 16px;
        }
        
        .metric-card {
            background: linear-gradient(135deg, #667eea15 0%, #764ba215 100%);
            border-radius: 12px;
            padding: 24px;
            text-align: center;
        }
        
        .metric-value {
            font-size: 36px;
            font-weight: 600;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin: 12px 0;
        }
        
        .metric-label {
            font-size: 12px;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-weight: 500;
        }
        
        .footer {
            text-align: center;
            padding: 24px;
            color: white;
            font-size: 14px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            backdrop-filter: blur(10px);
        }
        
        .loading {
            text-align: center;
            padding: 80px 20px;
            color: white;
        }
        
        .loading-spinner {
            border: 4px solid rgba(255, 255, 255, 0.3);
            border-top: 4px solid white;
            border-radius: 50%;
            width: 60px;
            height: 60px;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        @media (max-width: 768px) {
            .app-bar h1 {
                font-size: 28px;
            }
            
            .online-count {
                font-size: 72px;
            }
            
            .api-links {
                grid-template-columns: 1fr;
            }
            
            .api-buttons {
                flex-direction: column;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="app-bar">
            <h1>🚀 Hysteria UDP Manager</h1>
            <div class="subtitle">
                <span class="pulse-dot"></span>
                <span>Real-time Monitoring Dashboard</span>
            </div>
        </div>
        
        <div id="content">
            <div class="loading">
                <div class="loading-spinner"></div>
                <div>Loading dashboard...</div>
            </div>
        </div>
    </div>
    
    <script>
        async function fetchData() {
            try {
                const response = await fetch('/udpserver/system_info?t=' + Date.now());
                const data = await response.json();
                updateDashboard(data);
            } catch (error) {
                console.error('Error:', error);
                document.getElementById('content').innerHTML = `
                    <div class="loading">
                        <div>❌ Error loading data</div>
                    </div>
                `;
            }
        }
        
        function copyToClipboard(text, button) {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(() => {
                    showCopySuccess(button);
                }).catch(() => {
                    fallbackCopy(text, button);
                });
            } else {
                fallbackCopy(text, button);
            }
        }
        
        function fallbackCopy(text, button) {
            const textarea = document.createElement('textarea');
            textarea.value = text;
            textarea.style.position = 'fixed';
            textarea.style.opacity = '0';
            document.body.appendChild(textarea);
            textarea.select();
            
            try {
                document.execCommand('copy');
                showCopySuccess(button);
            } catch (err) {
                alert('Copy failed. URL: ' + text);
            }
            
            document.body.removeChild(textarea);
        }
        
        function showCopySuccess(button) {
            const originalHTML = button.innerHTML;
            button.innerHTML = '<span class="material-icons">check</span>Copied!';
            button.classList.add('copied');
            
            setTimeout(() => {
                button.innerHTML = originalHTML;
                button.classList.remove('copied');
            }, 2000);
        }
        
        function updateDashboard(data) {
            const hysteriaStatus = data.hysteria_status === 'online' ? 
                '<span class="status-badge online"><span class="material-icons">check_circle</span>Online</span>' :
                '<span class="status-badge offline"><span class="material-icons">cancel</span>Offline</span>';
            
            const webStatus = data.web_status === 'on' ? 
                '<span class="status-badge online"><span class="material-icons">check_circle</span>Active</span>' :
                '<span class="status-badge offline"><span class="material-icons">cancel</span>Inactive</span>';
            
            const apiJsonUrl = `http://${data.server_ip}/udpserver/online_app`;
            const apiTextUrl = `http://${data.server_ip}/udpserver/online`;
            
            document.getElementById('content').innerHTML = `
                <div class="card">
                    <div class="online-hero">
                        <div class="online-label">👥 Online Users</div>
                        <div class="online-count">${data.online}</div>
                    </div>
                </div>
                
                <div class="card">
                    <div class="card-title">
                        <span class="material-icons">info</span>
                        Server Information
                    </div>
                    <div class="info-grid">
                        <div class="info-item">
                            <div class="info-label">🌐 Domain</div>
                            <div class="info-value">${data.domain}</div>
                        </div>
                        <div class="info-item">
                            <div class="info-label">📡 Server IP</div>
                            <div class="info-value">${data.server_ip}</div>
                        </div>
                        <div class="info-item">
                            <div class="info-label">🔒 Obfuscation</div>
                            <div class="info-value">${data.obfuscation}</div>
                        </div>
                    </div>
                </div>
                
                <div class="card">
                    <div class="card-title">
                        <span class="material-icons">link</span>
                        API Endpoints
                    </div>
                    <div class="api-links">
                        <div class="api-link-card">
                            <div class="api-link-header">
                                <span class="material-icons">code</span>
                                <div class="api-link-title">📄 JSON API</div>
                            </div>
                            <div class="api-url-box">${apiJsonUrl}</div>
                            <div class="api-buttons">
                                <a href="${apiJsonUrl}" target="_blank" class="btn">
                                    <span class="material-icons">open_in_new</span>
                                    Open Link
                                </a>
                                <button class="btn" onclick="copyToClipboard('${apiJsonUrl}', this)">
                                    <span class="material-icons">content_copy</span>
                                    Copy Link
                                </button>
                            </div>
                        </div>
                        
                        <div class="api-link-card">
                            <div class="api-link-header">
                                <span class="material-icons">description</span>
                                <div class="api-link-title">📝 TEXT API</div>
                            </div>
                            <div class="api-url-box">${apiTextUrl}</div>
                            <div class="api-buttons">
                                <a href="${apiTextUrl}" target="_blank" class="btn">
                                    <span class="material-icons">open_in_new</span>
                                    Open Link
                                </a>
                                <button class="btn" onclick="copyToClipboard('${apiTextUrl}', this)">
                                    <span class="material-icons">content_copy</span>
                                    Copy Link
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="card">
                    <div class="card-title">
                        <span class="material-icons">power_settings_new</span>
                        Service Status
                    </div>
                    <div class="status-grid">
                        <div class="status-item">
                            <span class="status-label">Hysteria Server</span>
                            ${hysteriaStatus}
                        </div>
                        <div class="status-item">
                            <span class="status-label">Web Dashboard</span>
                            ${webStatus}
                        </div>
                    </div>
                </div>
                
                <div class="card">
                    <div class="card-title">
                        <span class="material-icons">analytics</span>
                        System Resources
                    </div>
                    <div class="metric-grid">
                        <div class="metric-card">
                            <div class="metric-label">CPU Cores</div>
                            <div class="metric-value">${data.cpu_cores}</div>
                        </div>
                        <div class="metric-card">
                            <div class="metric-label">CPU Usage</div>
                            <div class="metric-value">${data.cpu_usage}%</div>
                        </div>
                        <div class="metric-card">
                            <div class="metric-label">Memory Used</div>
                            <div class="metric-value">${data.mem_used}<small style="font-size: 14px;">MB</small></div>
                        </div>
                        <div class="metric-card">
                            <div class="metric-label">Memory Total</div>
                            <div class="metric-value">${data.mem_total}<small style="font-size: 14px;">MB</small></div>
                        </div>
                        <div class="metric-card">
                            <div class="metric-label">Memory Usage</div>
                            <div class="metric-value">${data.mem_percent}%</div>
                        </div>
                    </div>
                </div>
                
                <div class="footer">
                    <span class="material-icons" style="vertical-align: middle; font-size: 18px;">autorenew</span>
                    Auto-refresh every 3 seconds | Powered by Hysteria UDP
                </div>
            `;
        }
        
        fetchData();
        setInterval(fetchData, 3000);
    </script>
</body>
</html>
HTMLEOF
            
            chmod 644 "$WEB_DIR/index.html"
            
            # Update system info
            update_system_info
            
            if nginx -t >/dev/null 2>&1; then
                systemctl reload nginx
                local server_ip=$(get_ipv4)
                echo -e "${GREEN}✓ Web server turned ON${NC}"
                echo -e "${CYAN}Dashboard: http://${server_ip}/udpserver/${NC}"
                echo -e "${CYAN}API JSON:  http://${server_ip}/udpserver/online_app${NC}"
                echo -e "${CYAN}API TEXT:  http://${server_ip}/udpserver/online${NC}"
            else
                echo -e "${RED}✗ Nginx config test failed!${NC}"
                # If config test fails, remove the bad config to avoid breaking nginx
                rm -f /etc/nginx/sites-enabled/udp-status
            fi
        else
            echo -e "${YELLOW}Cancelled${NC}"
        fi
    fi
}
# =================================================================
# === အပေါ်က Function တစ်ခုလုံးကို အသစ်ပြင်ဆင်ထားပါသည် ===
# =================================================================

# User Management Functions
add_user() {
    echo -e "\n${BLUE}Add New User${NC}"
    echo -e "${BLUE}Enter username:${NC}"
    read -r username
    if [[ -z "$username" ]]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        return
    fi
    
    echo -e "${BLUE}Enter password:${NC}"
    read -r password
    if [[ -z "$password" ]]; then
        echo -e "${RED}Password cannot be empty.${NC}"
        return
    fi
    
    echo -e "${BLUE}Enter duration in days (e.g., 30). Enter 0 for unlimited:${NC}"
    read -r duration_days
    
    if ! [[ "$duration_days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid number of days.${NC}"
        return
    fi
    
    local expire_timestamp=0
    if [[ "$duration_days" -gt 0 ]]; then
        expire_timestamp=$(date -d "+$duration_days days" +%s)
        echo -e "${CYAN}User will expire on: $(date -d "@$expire_timestamp" '+%Y-%m-%d %H:%M:%S')${NC}"
    else
        echo -e "${CYAN}User has no expiration.${NC}"
    fi
    
    sqlite3 "$USER_DB" "INSERT INTO users (username, password, expire_date) VALUES ('$username', '$password', $expire_timestamp);" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ User '$username' added.${NC}"
        if update_userpass_config; then
            systemctl restart hysteria-server
        fi
    else
        echo -e "${RED}✗ Failed to add user (maybe '$username' already exists?)${NC}"
    fi
}

edit_user() {
    echo -e "\n${BLUE}Enter username to edit:${NC}"
    read -r username
    
    local user_exists=$(sqlite3 "$USER_DB" "SELECT id FROM users WHERE username='$username';" 2>/dev/null)
    if [[ -z "$user_exists" ]]; then
        echo -e "${RED}User '$username' not found.${NC}"
        return
    fi
    
    echo -e "${CYAN}Editing user: $username${NC}"
    echo "1. Change Password"
    echo "2. Set New Expiry Date"
    echo "Enter choice:"
    read -r choice
    
    local restart_needed=0
    
    case $choice in
        1)
            echo -e "${BLUE}Enter new password:${NC}"
            read -r password
            if [[ -z "$password" ]]; then
                echo -e "${RED}Password cannot be empty.${NC}"
                return
            fi
            sqlite3 "$USER_DB" "UPDATE users SET password = '$password' WHERE username = '$username';" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}✓ Password updated for '$username'.${NC}"
                restart_needed=1
            else
                echo -e "${RED}✗ Failed to update password.${NC}"
            fi
            ;;
        2)
            echo -e "${BLUE}Enter new duration in days (from today). Enter 0 for unlimited:${NC}"
            read -r duration_days
            
            if ! [[ "$duration_days" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Invalid number of days.${NC}"
                return
            fi
            
            local expire_timestamp=0
            if [[ "$duration_days" -gt 0 ]]; then
                expire_timestamp=$(date -d "+$duration_days days" +%s)
                echo -e "${CYAN}User will now expire on: $(date -d "@$expire_timestamp" '+%Y-%m-%d %H:%M:%S')${NC}"
            else
                echo -e "${CYAN}User expiration removed.${NC}"
            fi
            
            sqlite3 "$USER_DB" "UPDATE users SET expire_date = $expire_timestamp WHERE username = '$username';" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}✓ Expiry date updated for '$username'.${NC}"
                restart_needed=1
            else
                echo -e "${RED}✗ Failed to update expiry date.${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Invalid choice.${NC}"
            ;;
    esac
    
    if [[ "$restart_needed" -eq 1 ]]; then
        if update_userpass_config; then
            systemctl restart hysteria-server
        fi
    fi
}

delete_user() {
    echo -e "\n${BLUE}Enter username to delete:${NC}"
    read -r username
    
    sqlite3 "$USER_DB" "DELETE FROM users WHERE username = '$username';" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ User '$username' deleted.${NC}"
        if update_userpass_config; then
            systemctl restart hysteria-server
        fi
    else
        echo -e "${RED}✗ Failed to delete user.${NC}"
    fi
}

show_users() {
    echo -e "\n${BLUE}═══ Current Users ═══${NC}"
    local user_count=$(sqlite3 "$USER_DB" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
    echo -e "${CYAN}Total users: $user_count${NC}\n"
    
    if [[ $user_count -gt 0 ]]; then
        echo -e "${GREEN}Username\t\tPassword\t\tExpiry Date\t\tStatus${NC}"
        echo "────────────────────────────────────────────────────────────────────────────────"
        local now_ts=$(date +%s)
        
        sqlite3 "$USER_DB" "SELECT username, password, expire_date FROM users;" 2>/dev/null | while IFS='|' read -r username password expire_date; do
            local status
            local expiry_str
            
            if [[ "$expire_date" -eq 0 ]]; then
                expiry_str="Unlimited"
                status="${GREEN}Active${NC}"
            elif [[ "$expire_date" -gt "$now_ts" ]]; then
                expiry_str=$(date -d "@$expire_date" '+%Y-%m-%d %H:%M:%S')
                status="${GREEN}Active${NC}"
            else
                expiry_str=$(date -d "@$expire_date" '+%Y-%m-%d %H:%M:%S')
                status="${RED}Expired${NC}"
            fi
            
            echo -e "$(printf "%-20s\t%-20s\t%-20s\t" "$username" "$password" "$expiry_str")$status"
        done
    else
        echo -e "${YELLOW}No users found${NC}"
    fi
}

# Configuration Functions
change_config_value() {
    local key=$1
    local prompt_text=$2
    local is_numeric=$3
    
    echo -e "\n${BLUE}${prompt_text}${NC}"
    read -r value
    
    local new_value
    if [[ "$is_numeric" == "true" ]]; then
        if ! [[ "$value" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, must be numeric.${NC}"
            return
        fi
        new_value=$value
    else
        new_value="\"$value\""
    fi
    
    jq "$key = $new_value" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo -e "${GREEN}✓ $key changed${NC}"
    systemctl restart hysteria-server
}

set_connection_limit() {
    echo -e "\n${BLUE}Set Total Connection Limit${NC}"
    echo -e "${CYAN}This updates the 'limite' value in the JSON file for apps.${NC}"
    echo -e "${BLUE}Enter new total limit (e.g., 2500):${NC}"
    read -r limit
    
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid number.${NC}"
        return
    fi
    
    local onlines=$(grep -oP '"onlines":"\K[0-9]+(?=")' "$WEB_APP_FILE" 2>/dev/null || echo 0)
    
    echo "{\"onlines\":\"$onlines\",\"limite\":\"$limit\"}" > "$WEB_APP_FILE"
    chmod 666 "$WEB_APP_FILE" 2>/dev/null
    
    echo -e "${GREEN}✓ Connection limit set to $limit in $WEB_APP_FILE${NC}"
}

restart_server() {
    systemctl restart hysteria-server
    echo -e "${GREEN}✓ Server restarted${NC}"
}

stop_server() {
    systemctl stop hysteria-server
    echo -e "${YELLOW}Server stopped${NC}"
}

start_server() {
    systemctl start hysteria-server
    echo -e "${GREEN}✓ Server started${NC}"
}

uninstall_server() {
    echo -e "\n${RED}═══ WARNING: COMPLETE UNINSTALL ═══${NC}"
    echo -e "${YELLOW}This will stop all services and remove all related files${NC}"
    
    echo -e "\n${YELLOW}Uninstall Nginx? (yes/no) [default: no]${NC}"
    read -r remove_nginx
    echo -e "${YELLOW}Uninstall Redis? (yes/no) [default: no]${NC}"
    read -r remove_redis
    
    echo -e "\n${RED}Are you absolutely sure you want to proceed? (yes/no):${NC}"
    read -r confirm
    
    if [[ "$confirm" == "yes" ]]; then
        echo -e "${BLUE}Stopping services...${NC}"
        systemctl stop hysteria-online-monitor hysteria-tracker hysteria-server 2>/dev/null
        systemctl disable hysteria-online-monitor hysteria-tracker hysteria-server 2>/dev/null
        
        echo -e "${BLUE}Removing files...${NC}"
        rm -f /etc/systemd/system/hysteria-online-monitor.service
        rm -f /etc/systemd/system/hysteria-tracker.service
        rm -f /etc/systemd/system/hysteria-server.service
        rm -f /usr/local/bin/hysteria-online-monitor.sh
        rm -f /usr/local/bin/hysteria-tracker.sh
        rm -f /usr/local/bin/hysteria
        rm -f /usr/local/bin/udp # Remove the manager
        rm -f "$CRON_FILE"
        
        systemctl daemon-reload
        
        echo -e "${BLUE}Removing directories...${NC}"
        rm -rf "$CONFIG_DIR"
        rm -rf "$WEB_DIR"
        rm -rf "/var/log/hysteria"
        
        if [[ -f "/etc/nginx/sites-enabled/udp-status" ]]; then
            echo -e "${BLUE}Cleaning Nginx config...${NC}"
            rm -f /etc/nginx/sites-{enabled,available}/udp-status
            systemctl reload nginx 2>/dev/null
        fi
        
        if [[ "$remove_nginx" == "yes" ]]; then
            echo -e "${BLUE}Uninstalling Nginx...${NC}"
            systemctl stop nginx 2>/dev/null
            apt-get purge -y nginx nginx-common
        fi
        
        if [[ "$remove_redis" == "yes" ]]; then
            echo -e "${BLUE}Uninstalling Redis...${NC}"
            systemctl stop redis-server 2>/dev/null
            apt-get purge -y redis-server
            rm -rf /var/lib/redis
        fi
        
        echo -e "${GREEN}✓ Complete uninstall finished.${NC}"
    else
        echo -e "${YELLOW}Cancelled${NC}"
    fi
}

show_banner() {
    clear
    
    # Get system information
    local server_ip=$(get_ipv4)
    local domain=$(get_domain)
    local obfs=$(get_obfuscation)
    local online_count=$(cat "$WEB_STATUS_FILE" 2>/dev/null || echo "0")
    
    # CPU information
    local cpu_cores=$(nproc)
    
    # === CPU USAGE FIX (REPLACED top WITH vmstat) ===
    local cpu_usage="N/A"
    if command -v vmstat &> /dev/null; then
        cpu_usage=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
    fi

    # Memory information
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")
    
    # Service status
    local hysteria_status="${RED}● OFFLINE${NC}"
    if systemctl is-active hysteria-server >/dev/null 2>&1; then
        hysteria_status="${GREEN}● ONLINE${NC}"
    fi
    
    # Web server status
    local web_status
    if is_web_enabled; then
        web_status="${GREEN}● ON${NC}"
    else
        web_status="${RED}● OFF${NC}"
    fi
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${WHITE}HYSTERIA UDP MANAGER${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e "${BLUE}┌─ SYSTEM RESOURCES ──────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} ${YELLOW}CPU:${NC}    ${GREEN}$cpu_cores Core(s)${NC} - Usage: ${GREEN}${cpu_usage}%${NC}              ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC} ${YELLOW}Memory:${NC} ${GREEN}${mem_used}MB${NC} / ${CYAN}${mem_total}MB${NC} - Usage: ${GREEN}${mem_percent}%${NC}      ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo -e ""
    echo -e "${MAGENTA}┌─ SERVER INFORMATION ────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}│${NC} ${YELLOW}Domain:${NC}      ${GREEN}${domain}${NC}"
    echo -e "${MAGENTA}│${NC} ${YELLOW}Public IP:${NC}   ${GREEN}${server_ip}${NC}"
    echo -e "${MAGENTA}│${NC} ${YELLOW}Obfuscation:${NC} ${GREEN}${obfs}${NC}"
    echo -e "${MAGENTA}│${NC} ${YELLOW}Online:${NC}      ${GREEN}${online_count}${NC} users"
    echo -e "${MAGENTA}│${NC} ${YELLOW}Service:${NC}     $hysteria_status"
    echo -e "${MAGENTA}│${NC} ${YELLOW}Web Link:${NC}    $web_status"
    echo -e "${MAGENTA}└─────────────────────────────────────────────────────────────┘${NC}"
    
    # Only show links if web server is enabled
    if is_web_enabled; then
        echo -e ""
        echo -e "${GREEN}┌─ ONLINE LINKS ──────────────────────────────────────────────┐${NC}"
        echo -e "${GREEN}│${NC} ${CYAN}Dashboard:${NC} ${WHITE}http://${server_ip}/udpserver/${NC}"
        echo -e "${GREEN}│${NC} ${CYAN}API JSON:${NC}  ${WHITE}http://${server_ip}/udpserver/online_app${NC}"
        echo -e "${GREEN}│${NC} ${CYAN}API Text:${NC}  ${WHITE}http://${server_ip}/udpserver/online${NC}"
        echo -e "${GREEN}└─────────────────────────────────────────────────────────────┘${NC}"
    fi
}

show_menu() {
    echo -e "\n${BLUE}════════ UDP Manager Menu ════════${NC}"
    echo -e "${CYAN}--- User Management ---${NC}"
    echo -e "${GREEN}1.  Add new user (with Expiry)${NC}"
    echo -e "${GREEN}2.  Edit user (Password / Expiry)${NC}"
    echo -e "${GREEN}3.  Delete user${NC}"
    echo -e "${GREEN}4.  Show all users (with Password & Expiry)${NC}"
    echo -e "\n${CYAN}--- Monitoring ---${NC}"
    echo -e "${GREEN}5.  Show online users (IPs)${NC}"
    echo -e "${GREEN}6.  Show Redis statistics${NC}"
    echo -e "${GREEN}7.  Check service status${NC}"
    echo -e "\n${CYAN}--- Service Control ---${NC}"
    echo -e "${YELLOW}8.  Start monitor services${NC}"
    echo -e "${YELLOW}9.  Stop monitor services${NC}"
    echo -e "${YELLOW}10. Restart monitor services${NC}"
    echo -e "${GREEN}11. Restart Hysteria server${NC}"
    echo -e "${GREEN}12. Stop Hysteria server${NC}"
    echo -e "${GREEN}13. Start Hysteria server${NC}"
    echo -e "\n${CYAN}--- Configuration ---${NC}"
    echo -e "${GREEN}14. Toggle web server (ON/OFF)${NC}"
    echo -e "${GREEN}15. Change domain (server_name)${NC}"
    echo -e "${GREEN}16. Change obfuscation${NC}"
    echo -e "${GREEN}17. Change upload speed${NC}"
    echo -e "${GREEN}18. Change download speed${NC}"
    echo -e "${GREEN}19. Set total connection limit (for app)${NC}"
    echo -e "\n${CYAN}--- Maintenance ---${NC}"
    echo -e "${YELLOW}20. Clear Redis session data${NC}"
    echo -e "${RED}21. Uninstall ALL${NC}"
    echo -e "${BLUE}22. Exit${NC}"
    echo -e "${BLUE}═════════════════════════════════${NC}"
    echo -n "Enter your choice: "
}

# =================================================================
# === Main Script Execution ===
# =================================================================

# This script is called by `udp` (itself)
if [[ "$1" == "updateconfig" ]]; then
    if [[ ! -f "$USER_DB" || ! -f "$CONFIG_FILE" ]]; then
        exit 1
    fi
    
    if update_userpass_config; then
        systemctl restart hysteria-server
    fi
    exit 0
fi

# This is the normal 'udp' command execution
# Initialize
echo -e "${BLUE}Initializing UDP Manager (Optimized Edition)...${NC}"
install_dependencies # Check dependencies
init_database
setup_user_expiry_cron # Ensure cron is set
setup_online_monitor_service # Ensure monitor is set
setup_tracker_service # Ensure tracker is set

show_banner

# Auto-start services if not running
if ! systemctl is-active hysteria-online-monitor >/dev/null 2>&1; then
    echo -e "${YELLOW}Auto-starting online monitor...${NC}"
    start_online_monitor
fi

if ! systemctl is-active hysteria-tracker >/dev/null 2>&1; then
    echo -e "${YELLOW}Auto-starting connection tracker...${NC}"
    start_connection_tracker
fi

# Main loop
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) add_user ;;
        2) edit_user ;;
        3) delete_user ;;
        4) show_users ;;
        5) show_online_users ;;
        6) show_redis_stats ;;
        7) check_monitor_status ;;
        8) start_online_monitor && start_connection_tracker ;;
        9) stop_online_monitor && stop_connection_tracker ;;
        10) systemctl restart hysteria-online-monitor hysteria-tracker ;;
        11) restart_server ;;
        12) stop_server ;;
        13) start_server ;;
        14) toggle_web_server ;;
        15) change_config_value ".listen" "Enter new domain:port (e.g., :443 or example.com:443):" false ;;
        16) change_config_value ".obfs" "Enter new obfuscation:" false ;;
        17) change_config_value ".up_mbps" "Enter new upload speed (Mbps):" true ;;
        18) change_config_value ".down_mbps" "Enter new download speed (Mbps):" true ;;
        19) set_connection_limit ;;
        20) clear_redis_data ;;
        21) uninstall_server ;;
        22) 
            echo -e "${YELLOW}Exiting (services continue in background)...${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}✗ Invalid choice${NC}"
            ;;
    esac
    
    echo -e "\n${CYAN}Press Enter to continue...${NC}"
    read -r
    show_banner
done
