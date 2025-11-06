#!/usr/bin/env bash
#
# Try `install_shanvpn.sh --help` for usage.
#
# (c) 2025 SHANVPN
#

set -e

# Domain Name
DOMAIN="vpn.khaledagn.me"

# PROTOCOL
PROTOCOL="udp"

# UDP PORT
UDP_PORT=":36712"

# OBFS
OBFS="shanvpn"

# PASSWORDS
PASSWORD="shanvpn"

# Script paths
SCRIPT_NAME="$(basename "$0")"
SCRIPT_ARGS=("$@")
EXECUTABLE_INSTALL_PATH="/usr/local/bin/hysteria"
SYSTEMD_SERVICES_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/hysteria"
USER_DB="$CONFIG_DIR/udpusers.db"
REPO_URL="https://github.com/apernet/hysteria"
CONFIG_FILE="$CONFIG_DIR/config.json"
API_BASE_URL="https://api.github.com/repos/apernet/hysteria"
CURL_FLAGS=(-L -f -q --retry 5 --retry-delay 10 --retry-max-time 60)
PACKAGE_MANAGEMENT_INSTALL="${PACKAGE_MANAGEMENT_INSTALL:-}"
SYSTEMD_SERVICE="$SYSTEMD_SERVICES_DIR/hysteria-server.service"
mkdir -p "$CONFIG_DIR"
touch "$USER_DB"

# Other configurations
OPERATING_SYSTEM=""
ARCHITECTURE=""
HYSTERIA_USER=""
HYSTERIA_HOME_DIR=""
VERSION=""
FORCE=""
LOCAL_FILE=""
FORCE_NO_ROOT=""
FORCE_NO_SYSTEMD=""

# Utility functions
has_command() {
    local _command=$1
    type -P "$_command" > /dev/null 2>&1
}

curl() {
    command curl "${CURL_FLAGS[@]}" "$@"
}

mktemp() {
    command mktemp "$@" "hyservinst.XXXXXXXXXX"
}

tput() {
    if has_command tput; then
        command tput "$@"
    fi
}

tred() {
    tput setaf 1
}

tgreen() {
    tput setaf 2
}

tyellow() {
    tput setaf 3
}

tblue() {
    tput setaf 4
}

taoi() {
    tput setaf 6
}

tbold() {
    tput bold
}

treset() {
    tput sgr0
}

note() {
    local _msg="$1"
    echo -e "$SCRIPT_NAME: $(tbold)note: $_msg$(treset)"
}

warning() {
    local _msg="$1"
    echo -e "$SCRIPT_NAME: $(tyellow)warning: $_msg$(treset)"
}

error() {
    local _msg="$1"
    echo -e "$SCRIPT_NAME: $(tred)error: $_msg$(treset)"
}

show_argument_error_and_exit() {
    local _error_msg="$1"
    error "$_error_msg"
    echo "Try \"$0 --help\" for the usage." >&2
    exit 22
}

install_content() {
    local _install_flags="$1"
    local _content="$2"
    local _destination="$3"

    local _tmpfile="$(mktemp)"

    echo -ne "Install $_destination ... "
    echo "$_content" > "$_tmpfile"
    if install "$_install_flags" "$_tmpfile" "$_destination"; then
        echo -e "ok"
    fi

    rm -f "$_tmpfile"
}

remove_file() {
    local _target="$1"

    echo -ne "Remove $_target ... "
    if rm "$_target"; then
        echo -e "ok"
    fi
}

exec_sudo() {
    local _saved_ifs="$IFS"
    IFS=$'\n'
    local _preserved_env=(
        $(env | grep "^PACKAGE_MANAGEMENT_INSTALL=" || true)
        $(env | grep "^OPERATING_SYSTEM=" || true)
        $(env | grep "^ARCHITECTURE=" || true)
        $(env | grep "^HYSTERIA_\w*=" || true)
        $(env | grep "^FORCE_\w*=" || true)
    )
    IFS="$_saved_ifs"

    exec sudo env \
    "${_preserved_env[@]}" \
    "$@"
}

install_software() {
    local package="$1"
    if has_command apt-get; then
        echo "Installing $package using apt-get..."
        apt-get update && apt-get install -y "$package"
    elif has_command dnf; then
        echo "Installing $package using dnf..."
        dnf install -y "$package"
    elif has_command yum; then
        echo "Installing $package using yum..."
        yum install -y "$package"
    elif has_command zypper; then
        echo "Installing $package using zypper..."
        zypper install -y "$package"
    elif has_command pacman; then
        echo "Installing $package using pacman..."
        pacman -Sy --noconfirm "$package"
    else
        echo "Error: No supported package manager found. Please install $package manually."
        exit 1
    fi
}

is_user_exists() {
    local _user="$1"
    id "$_user" > /dev/null 2>&1
}

check_permission() {
    if [[ "$UID" -eq '0' ]]; then
        return
    fi

    note "The user currently executing this script is not root."

    case "$FORCE_NO_ROOT" in
        '1')
            warning "FORCE_NO_ROOT=1 is specified, we will process without root and you may encounter the insufficient privilege error."
            ;;
        *)
            if has_command sudo; then
                note "Re-running this script with sudo, you can also specify FORCE_NO_ROOT=1 to force this script running with current user."
                exec_sudo "$0" "${SCRIPT_ARGS[@]}"
            else
                error "Please run this script with root or specify FORCE_NO_ROOT=1 to force this script running with current user."
                exit 13
            fi
            ;;
    esac
}

check_environment_operating_system() {
    if [[ -n "$OPERATING_SYSTEM" ]]; then
        warning "OPERATING_SYSTEM=$OPERATING_SYSTEM is specified, operating system detection will not be performed."
        return
    fi

    if [[ "x$(uname)" == "xLinux" ]]; then
        OPERATING_SYSTEM=linux
        return
    fi

    error "This script only supports Linux."
    note "Specify OPERATING_SYSTEM=[linux|darwin|freebsd|windows] to bypass this check and force this script running on this $(uname)."
    exit 95
}

check_environment_architecture() {
    if [[ -n "$ARCHITECTURE" ]]; then
        warning "ARCHITECTURE=$ARCHITECTURE is specified, architecture detection will not be performed."
        return
    fi

    case "$(uname -m)" in
        'i386' | 'i686')
            ARCHITECTURE='386'
            ;;
        'amd64' | 'x86_64')
            ARCHITECTURE='amd64'
            ;;
        'armv5tel' | 'armv6l' | 'armv7' | 'armv7l')
            ARCHITECTURE='arm'
            ;;
        'armv8' | 'aarch64')
            ARCHITECTURE='arm64'
            ;;
        'mips' | 'mipsle' | 'mips64' | 'mips64le')
            ARCHITECTURE='mipsle'
            ;;
        's390x')
            ARCHITECTURE='s390x'
            ;;
        *)
            error "The architecture '$(uname -a)' is not supported."
            note "Specify ARCHITECTURE=<architecture> to bypass this check and force this script running on this $(uname -m)."
            exit 8
            ;;
    esac
}

check_environment_systemd() {
    if [[ -d "/run/systemd/system" ]] || grep -q systemd <(ls -l /sbin/init); then
        return
    fi

    case "$FORCE_NO_SYSTEMD" in
        '1')
            warning "FORCE_NO_SYSTEMD=1 is specified, we will process as normal even if systemd is not detected by us."
            ;;
        '2')
            warning "FORCE_NO_SYSTEMD=2 is specified, we will process but all systemd related commands will not be executed."
            ;;
        *)
            error "This script only supports Linux distributions with systemd."
            note "Specify FORCE_NO_SYSTEMD=1 to disable this check and force this script running as systemd is detected."
            note "Specify FORCE_NO_SYSTEMD=2 to disable this check along with all systemd related commands."
            ;;
    esac
}

parse_arguments() {
    while [[ "$#" -gt '0' ]]; do
        case "$1" in
            '--remove')
                if [[ -n "$OPERATION" && "$OPERATION" != 'remove' ]]; then
                    show_argument_error_and_exit "Option '--remove' is conflicted with other options."
                fi
                OPERATION='remove'
                ;;
            '--version')
                VERSION="$2"
                if [[ -z "$VERSION" ]]; then
                    show_argument_error_and_exit "Please specify the version for option '--version'."
                fi
                shift
                if ! [[ "$VERSION" == v* ]]; then
                    show_argument_error_and_exit "Version numbers should begin with 'v' (such like 'v1.3.1'), got '$VERSION'"
                fi
                ;;
            '-h' | '--help')
                show_usage_and_exit
                ;;
            '-l' | '--local')
                LOCAL_FILE="$2"
                if [[ -z "$LOCAL_FILE" ]]; then
                    show_argument_error_and_exit "Please specify the local binary to install for option '-l' or '--local'."
                fi
                break
                ;;
            *)
                show_argument_error_and_exit "Unknown option '$1'"
                ;;
        esac
        shift
    done

    if [[ -z "$OPERATION" ]]; then
        OPERATION='install'
    fi

    # validate arguments
    case "$OPERATION" in
        'install')
            if [[ -n "$VERSION" && -n "$LOCAL_FILE" ]]; then
                show_argument_error_and_exit '--version and --local cannot be specified together.'
            fi
            ;;
        *)
            if [[ -n "$VERSION" ]]; then
                show_argument_error_and_exit "--version is only available when installing."
            fi
            if [[ -n "$LOCAL_FILE" ]]; then
                show_argument_error_and_exit "--local is only available when installing."
            fi
            ;;
    esac
}

check_hysteria_homedir() {
    local _default_hysteria_homedir="$1"

    if [[ -n "$HYSTERIA_HOME_DIR" ]]; then
        return
    fi

    if ! is_user_exists "$HYSTERIA_USER"; then
        HYSTERIA_HOME_DIR="$_default_hysteria_homedir"
        return
    fi

    HYSTERIA_HOME_DIR="$(eval echo ~"$HYSTERIA_USER")"
}

download_hysteria() {
    local _version="$1"
    local _destination="$2"

    local _download_url="$REPO_URL/releases/download/v1.3.5/hysteria-$OPERATING_SYSTEM-$ARCHITECTURE"
    echo "Downloading hysteria archive: $_download_url ..."
    if ! curl -R -H 'Cache-Control: no-cache' "$_download_url" -o "$_destination"; then
        error "Download failed! Please check your network and try again."
        return 11
    fi
    return 0
}

check_hysteria_user() {
    local _default_hysteria_user="$1"

    if [[ -n "$HYSTERIA_USER" ]]; then
        return
    fi

    if [[ ! -e "$SYSTEMD_SERVICES_DIR/hysteria-server.service" ]]; then
        HYSTERIA_USER="$_default_hysteria_user"
        return
    fi

    HYSTERIA_USER="$(grep -o '^User=\w*' "$SYSTEMD_SERVICES_DIR/hysteria-server.service" | tail -1 | cut -d '=' -f 2 || true)"

    if [[ -z "$HYSTERIA_USER" ]]; then
        HYSTERIA_USER="$_default_hysteria_user"
    fi
}

check_environment_curl() {
    if ! has_command curl; then
        install_software "curl"
    fi
}

check_environment_grep() {
    if ! has_command grep; then
        install_software "grep"
    fi
}

check_environment_sqlite3() {
    if ! has_command sqlite3; then
        install_software "sqlite3"
    fi
}

check_environment_pip() {
    if ! has_command pip; then
        install_software "pip"
    fi
}

check_environment_jq() {
    if ! has_command jq; then
        install_software "jq"
    fi
}

check_environment() {
    check_environment_operating_system
    check_environment_architecture
    check_environment_systemd
    check_environment_curl
    check_environment_grep
    check_environment_pip
    check_environment_sqlite3
    check_environment_jq
}

show_usage_and_exit() {
    echo
    echo -e "\t$(tbold)$SCRIPT_NAME$(treset) - SHANVPN server install script"
    echo
    echo -e "Usage:"
    echo
    echo -e "$(tbold)Install SHANVPN$(treset)"
    echo -e "\t$0 [ -f | -l <file> | --version <version> ]"
    echo -e "Flags:"
    echo -e "\t-f, --force\tForce re-install latest or specified version even if it has been installed."
    echo -e "\t-l, --local <file>\tInstall specified SHANVPN binary instead of download it."
    echo -e "\t--version <version>\tInstall specified version instead of the latest."
    echo
    echo -e "$(tbold)Remove SHANVPN$(treset)"
    echo -e "\t$0 --remove"
    echo
    echo -e "$(tbold)Check for the update$(treset)"
    echo -e "\t$0 -c"
    echo -e "\t$0 --check"
    echo
    echo -e "$(tbold)Show this help$(treset)"
    echo -e "\t$0 -h"
    echo -e "\t$0 --help"
    exit 0
}

tpl_hysteria_server_service_base() {
    local _config_name="$1"

    cat << EOF
[Unit]
Description=SHANVPN Service
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/etc/hysteria
Environment="PATH=/usr/local/bin/hysteria"
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.json

[Install]
WantedBy=multi-user.target
EOF
}

tpl_hysteria_server_service() {
    tpl_hysteria_server_service_base 'config'
}

tpl_hysteria_server_x_service() {
    tpl_hysteria_server_service_base '%i'
}



tpl_etc_hysteria_config_json() {
    local_users=$(fetch_users)

    mkdir -p "$CONFIG_DIR"

    cat << EOF > "$CONFIG_FILE"
{
  "server": "$DOMAIN",
  "listen": "$UDP_PORT",
  "protocol": "$PROTOCOL",
  "ca": "/etc/hysteria/ca.crt",
  "cert": "/etc/hysteria/hysteria.server.crt",
  "key": "/etc/hysteria/hysteria.server.key",
  "up": "100 Mbps",
  "up_mbps": 100,
  "down": "100 Mbps",
  "down_mbps": 100,
  "disable_udp": false,
  "insecure": false,
  "obfs": "$OBFS",
  "auth": {
 	"mode": "passwords",
  "config": [
      "$(echo $local_users)"
    ]
         }
}
EOF
}



setup_db() {
    echo "Setting up database"
    mkdir -p "$(dirname "$USER_DB")"

    if [[ ! -f "$USER_DB" ]]; then
        # Create the database file
        sqlite3 "$USER_DB" ".databases"
        if [[ $? -ne 0 ]]; then
            echo "Error: Unable to create database file at $USER_DB"
            exit 1
        fi
    fi

    # Create the users table
    sqlite3 "$USER_DB" <<EOF
CREATE TABLE IF NOT EXISTS users (
    username TEXT PRIMARY KEY,
    password TEXT NOT NULL
);
EOF

    # Check if the table 'users' was created successfully
    table_exists=$(sqlite3 "$USER_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';")
    if [[ "$table_exists" == "users" ]]; then
        echo "Database setup completed successfully. Table 'users' exists."
        
        # Add a default user if not already exists
        default_username="default"
        default_password="password"
        user_exists=$(sqlite3 "$USER_DB" "SELECT username FROM users WHERE username='$default_username';")
        
        if [[ -z "$user_exists" ]]; then
            sqlite3 "$USER_DB" "INSERT INTO users (username, password) VALUES ('$default_username', '$default_password');"
            if [[ $? -eq 0 ]]; then
                echo "Default user created successfully."
            else
                echo "Error: Failed to create default user."
            fi
        else
            echo "Default user already exists."
        fi
    else
        echo "Error: Table 'users' was not created successfully."
        # Show the database schema for debugging
        echo "Current database schema:"
        sqlite3 "$USER_DB" ".schema"
        exit 1
    fi
}


fetch_users() {
    DB_PATH="/etc/hysteria/udpusers.db"
    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" "SELECT username || ':' || password FROM users;" | paste -sd, -
    fi
}


perform_install_hysteria_binary() {
    if [[ -n "$LOCAL_FILE" ]]; then
        note "Performing local install: $LOCAL_FILE"

        echo -ne "Installing hysteria executable ... "

        if install -Dm755 "$LOCAL_FILE" "$EXECUTABLE_INSTALL_PATH"; then
            echo "ok"
        else
            exit 2
        fi

        return
    fi

    local _tmpfile=$(mktemp)

    if ! download_hysteria "$VERSION" "$_tmpfile"; then
        rm -f "$_tmpfile"
        exit 11
    fi

    echo -ne "Installing hysteria executable ... "

    if install -Dm755 "$_tmpfile" "$EXECUTABLE_INSTALL_PATH"; then
        echo "ok"
    else
        exit 13
    fi

    rm -f "$_tmpfile"
}

perform_remove_hysteria_binary() {
    remove_file "$EXECUTABLE_INSTALL_PATH"
}

perform_install_hysteria_example_config() {
    tpl_etc_hysteria_config_json
}

perform_install_hysteria_systemd() {
    if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
        return
    fi

    install_content -Dm644 "$(tpl_hysteria_server_service)" "$SYSTEMD_SERVICES_DIR/hysteria-server.service"
    install_content -Dm644 "$(tpl_hysteria_server_x_service)" "$SYSTEMD_SERVICES_DIR/hysteria-server@.service"

    systemctl daemon-reload
}

perform_remove_hysteria_systemd() {
    remove_file "$SYSTEMD_SERVICES_DIR/hysteria-server.service"
    remove_file "$SYSTEMD_SERVICES_DIR/hysteria-server@.service"

    systemctl daemon-reload
}

perform_install_hysteria_home_legacy() {
    if ! is_user_exists "$HYSTERIA_USER"; then
        echo -ne "Creating user $HYSTERIA_USER ... "
        useradd -r -d "$HYSTERIA_HOME_DIR" -m "$HYSTERIA_USER"
        echo "ok"
    fi
}

perform_install_manager_script() {
    local _manager_script="/usr/local/bin/shanvpn_manager.sh"
    local _symlink_path="/usr/local/bin/shanvpn"
    
    echo "Downloading manager script..."
    curl -o "$_manager_script" "https://hunmai.github.io/ovpn-th/Udp/shanvpn_manager.sh"
    chmod +x "$_manager_script"
    
    echo "Creating symbolic link to run the manager script using 'shanvpn' command..."
    ln -sf "$_manager_script" "$_symlink_path"
    
    echo "Manager script installed at $_manager_script"
    echo "You can now run the manager using the 'shanvpn' command."
}


is_hysteria_installed() {
    # RETURN VALUE
    # 0: hysteria is installed
    # 1: hysteria is not installed
    
    if [[ -f "$EXECUTABLE_INSTALL_PATH" || -h "$EXECUTABLE_INSTALL_PATH" ]]; then
        return 0
    fi
    return 1
}

get_running_services() {
    if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
        return
    fi
    
    systemctl list-units --state=active --plain --no-legend \
    | grep -o "hysteria-server@*[^\s]*.service" || true
}

restart_running_services() {
    if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
        return
    fi
    
    echo "Restarting running service ... "
    
    for service in $(get_running_services); do
        echo -ne "Restarting $service ... "
        systemctl restart "$service"
        echo "done"
    done
}

stop_running_services() {
    if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
        return
    fi
    
    echo "Stopping running service ... "
    
    for service in $(get_running_services); do
        echo -ne "Stopping $service ... "
        systemctl stop "$service"
        echo "done"
    done
}

perform_install() {
    local _is_fresh_install
    if ! is_hysteria_installed; then
        _is_fresh_install=1
    fi

    perform_install_hysteria_binary
    perform_install_hysteria_example_config
    perform_install_hysteria_home_legacy
    perform_install_hysteria_systemd
    setup_ssl
    start_services
    perform_install_manager_script

    if [[ -n "$_is_fresh_install" ]]; then
        echo
        echo -e "$(tbold)Congratulations! SHANVPN has been successfully installed on your server.$(treset)"
        echo "Use 'shanvpn' command to access the manager."

        echo
        echo -e "$(tbold)Client app SHANVPN:$(treset)"
        echo -e "$(tblue)https://play.google.com/store/apps/details?id=com.shanvpn.vpnth$(treset)"
        echo
        echo -e "Follow me!"
        echo
        echo -e "\t+ Check out my website at $(tblue)https://https://shanvpn.netlify.app/$(treset)"
        echo -e "\t+ Follow me on Telegram: $(tblue)https://t.me/ovpnth$(treset)"
        echo -e "\t+ Follow me on Facebook: $(tblue)https://www.facebook.com/share/1ZXAprCkwG/$(treset)"
        echo
    else
        restart_running_services
        start_services
        echo
        echo -e "$(tbold)SHANVPN has been successfully updated to $VERSION.$(treset)"
        echo
    fi
}

perform_remove() {
    perform_remove_hysteria_binary
    stop_running_services
    perform_remove_hysteria_systemd

    echo
    echo -e "$(tbold)Congratulations! SHANVPN has been successfully removed from your server.$(treset)"
    echo
    echo -e "You still need to remove configuration files and ACME certificates manually with the following commands:"
    echo
    echo -e "\t$(tred)rm -rf "$CONFIG_DIR"$(treset)"
    if [[ "x$HYSTERIA_USER" != "xroot" ]]; then
        echo -e "\t$(tred)userdel -r "$HYSTERIA_USER"$(treset)"
    fi
    if [[ "x$FORCE_NO_SYSTEMD" != "x2" ]]; then
        echo
        echo -e "You still might need to disable all related systemd services with the following commands:"
        echo
        echo -e "\t$(tred)rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service$(treset)"
        echo -e "\t$(tred)rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service$(treset)"
        echo -e "\t$(tred)systemctl daemon-reload$(treset)"
    fi
    echo
}

setup_ssl() {
    echo "Installing SSL certificates"
    
cat <<-EOF >/etc/hysteria/ca.crt
-----BEGIN CERTIFICATE-----
MIIE0zCCA7ugAwIBAgIJAPmnobGw0ywUMA0GCSqGSIb3DQEBCwUAMIGcMQswCQYD
VQQGEwJUSDETMBEGA1UECAwKQ2hpYW5nIFJhaTEMMAoGA1UEBwwDUGFuMQ8wDQYD
VQQKDAZUSC1WUE4xGzAZBgNVBAsMElBhbm5hd2l0IE5hcmVlZGVjaDEWMBQGA1UE
AwwNdGgtdnBuLmluLm5ldDEkMCIGCSqGSIb3DQEJARYVc3VwcG9ydEB0aC12cG4u
aW4ubmV0MCAXDTIzMDEyNzExNTA1NloYDzQ3NjAxMjIzMTE1MDU2WjCBnDELMAkG
A1UEBhMCVEgxEzARBgNVBAgMCkNoaWFuZyBSYWkxDDAKBgNVBAcMA1BhbjEPMA0G
A1UECgwGVEgtVlBOMRswGQYDVQQLDBJQYW5uYXdpdCBOYXJlZWRlY2gxFjAUBgNV
BAMMDXRoLXZwbi5pbi5uZXQxJDAiBgkqhkiG9w0BCQEWFXN1cHBvcnRAdGgtdnBu
LmluLm5ldDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMmUTCi/SPpx
+yS+Pmw38YkIIcw96Y1RwKwfC641eyUBNGqYNYsfFuVcSru17WGtsQ4ZCayXWT+j
8kLLoIOq2ryCg4JDvZrDYcnu0g9kJ2zzVohfDJCIjqZ1rBrnsPdchxRQ8JxsmlGK
R30s1RjulvTHWCE9/K7sq5qV6ortAk2hwFSAmJXQOrQbaYU497WBvE1zUaCY5ihk
8N6zDYQBcZosW2II1zwNU1vEwANfj8fLBaq/vpXZxkk+WmB7SpkmP6OPzXwZV4fl
YR7BV4aCbZk5QtvMJcVrPtMWg/giJwmTTydGVuiEJSLzxp+9PkqlxhqxCN88SBO4
+hfweoyfim8CAwEAAaOCARIwggEOMB0GA1UdDgQWBBSYKHQmnogRHUBvk1XZWmPv
f/N4LjCB0QYDVR0jBIHJMIHGgBSYKHQmnogRHUBvk1XZWmPvf/N4LqGBoqSBnzCB
nDELMAkGA1UEBhMCVEgxEzARBgNVBAgMCkNoaWFuZyBSYWkxDDAKBgNVBAcMA1Bh
bjEPMA0GA1UECgwGVEgtVlBOMRswGQYDVQQLDBJQYW5uYXdpdCBOYXJlZWRlY2gx
FjAUBgNVBAMMDXRoLXZwbi5pbi5uZXQxJDAiBgkqhkiG9w0BCQEWFXN1cHBvcnRA
dGgtdnBuLmluLm5ldIIJAPmnobGw0ywUMAwGA1UdEwQFMAMBAf8wCwYDVR0PBAQD
AgEGMA0GCSqGSIb3DQEBCwUAA4IBAQBRQCBkx3/YLoSmPQYwt5mWhOhJy9buDIgo
Br+zknPi4csanbABA/nfz7xK/ec7oquOpAVptBGVbhx2YW9m+kTNVfBW9l3lU7IS
kbn/xW7a80SYWlI12zKq9mhvQlGGPU5QiDBTPFOszo495ZRAqO6nlwxFzG1bd4ec
8AwgN72NqK/BIrNBSVL3uF61GzHJZBgjqLOazNcxCOuvDlDzIvCd8tfvSOByTaGD
8oBzkDNacITPcWpeiYBr+VE2rCxd2Lz2KKkuEDUSnpOKFgIq3gKx2HV2pIb3aG/j
dO40fyrZBdazciVvL0QVxbtTG5hulJ2xkSDVR7gMV3nxqaJyEzoj
-----END CERTIFICATE-----
EOF

cat <<-EOF >/etc/hysteria/hysteria.server.key
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDggniT/CuLh4cw
zYyj6wYn8dxL1opQEem15RdeRAQGXYOwcVlrryuljba1tsqPtdnkG3GPEmfZUaDH
1ui9Mr+r8R7QSep7TtuCrHQi3gfvoOKwbVzaeGHNmabTHX4XxzupPxqPStKU2y65
lU2FjIiVndqnQxfwCCP4CbgkURRU5sc5Y+LTUI2UsYcZx9vg122oD9slWEaTmJGb
l7+zzGwHmSgEME6IhkOjomX4r97HowRX7LHJdOY2bjRij2aCH9Cr5cULzUst5Mrt
CH+dpGkxuDP4Lhqx+7DDeAOxkgDW302dbQcyDvhsgFgOoyH22KnmuapDGQYYFrxz
hzgAu6zpAgMBAAECggEBAIr/XCXK5y7QrtuBN0S5Gquaa1issB9Yp8iM2IXtOEy0
kvanhsRLxIsQDQG99PU6kndOomUA8Tiz+AYhwSB6Df8nHnu4d6r2LKNfn9uCeYlb
o121p9o+09aV/ZoRVWLlX8OuJQR4P54XgXs2u7MmSd3PyHLr8CMU9yf25IHfjOXu
fg+JDOohhVq2yx3a7Y2GNrcpmGugvaKAHpPaS7D0SZhSqwVsQVwPDzWgMpRXe/LO
5kxkUateV/RxZ0sLOxnnp5A1eRrkChXbftybEJuuFOKbTivOEqasolw1cayI9Lln
6RsC9crgPdx9ZYfX29FBxoLoD/kryyF/+lMKWUf8bgECgYEA/3GaZVdSNIlY/uo3
15xkx5WRZ0Xh2599ntRqrLsG3T2lPKdYF/BNykquSfUjKCSdp9662Wj02mTgz7K3
1f3WLVSbEtUk6dxcwZm3IrkG7qjJDuiJcdlUMFqkxDtq8rwVF9wY2C04bcnZt/9m
sU8/PprMW40vUJW4zMK3mqWgsUECgYEA4P+fq1U597pnIF/t7ZbBEmTxJVIWx5qo
6dtaoVIZVeZ89iuBC5g/34W3KqRI+zEdHXXnVpi3S3Fj1EuvUqc2EEp4loniAm1d
R7E52MPkCDMdInrbDJd4mRereykJSUImTbzCr6D3xjjcdMHbON35tpMsoN5uyG9w
NyfyATEzaakCgYAKx/KqQEs56GoXKC9/LBycx9VBNJPZvxuALprp+2LIx6dHrhBr
wjqmRQyiFnSLZzA4O5BLSMC8zvEmEvbrUzFM7Hs3CkPqkuBfU2uFTaXbQMhrlqjm
YzPIbqrxlUhoQkPpo+JwjUgKajCEMYVWCnAy5jmly4mprwgDrFwvbLohgQKBgQDB
9LoAqVxqKB7kMq3ZJR7Uq32RbX1DnhhEWBp9fFdozGMmloQMqbdOCWfHc42SNFlj
3xKIfOdtOpcTGBdPyeL6Eih3pO7Wps5FkgpKyTsWsnFIGt4fsad9WYEyj0J5C3QX
iUPOwJU3JCcu4zoGgJvV/nL3Tifz0tTKRz4ANxiZ2QKBgANCKEU6H5JmrBGDX25E
TrwU6YZfYas4Rvn0tZwWg+YAM/CJ4Ipk/T83xtU6B7/cr/xr/AYDDUk+W4IGRERF
4yiB8mTRijKc/aLPv2YZGUPpUlUcoamUikXbiihQREi+r3xLMUHQFidiMtJKPhP7
60JxlEPFLeZz/KHhEZEK0HGD
-----END PRIVATE KEY-----
EOF

cat <<-EOF >/etc/hysteria/hysteria.server.crt
-----BEGIN CERTIFICATE-----
MIIE7DCCA9SgAwIBAgIQAPDEr5bCEVRDjm50PZUxZzANBgkqhkiG9w0BAQsFADCB
nDELMAkGA1UEBhMCVEgxEzARBgNVBAgMCkNoaWFuZyBSYWkxDDAKBgNVBAcMA1Bh
bjEPMA0GA1UECgwGVEgtVlBOMRswGQYDVQQLDBJQYW5uYXdpdCBOYXJlZWRlY2gx
FjAUBgNVBAMMDXRoLXZwbi5pbi5uZXQxJDAiBgkqhkiG9w0BCQEWFXN1cHBvcnRA
dGgtdnBuLmluLm5ldDAgFw0yMzAxMjcxMTU0MDNaGA80NzYwMTIyMzExNTQwM1ow
gZwxCzAJBgNVBAYTAlRIMRMwEQYDVQQIDApDaGlhbmcgUmFpMQwwCgYDVQQHDANQ
YW4xDzANBgNVBAoMBlRILVZQTjEbMBkGA1UECwwSUGFubmF3aXQgTmFyZWVkZWNo
MRYwFAYDVQQDDA10aC12cG4uaW4ubmV0MSQwIgYJKoZIhvcNAQkBFhVzdXBwb3J0
QHRoLXZwbi5pbi5uZXQwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDg
gniT/CuLh4cwzYyj6wYn8dxL1opQEem15RdeRAQGXYOwcVlrryuljba1tsqPtdnk
G3GPEmfZUaDH1ui9Mr+r8R7QSep7TtuCrHQi3gfvoOKwbVzaeGHNmabTHX4Xxzup
PxqPStKU2y65lU2FjIiVndqnQxfwCCP4CbgkURRU5sc5Y+LTUI2UsYcZx9vg122o
D9slWEaTmJGbl7+zzGwHmSgEME6IhkOjomX4r97HowRX7LHJdOY2bjRij2aCH9Cr
5cULzUst5MrtCH+dpGkxuDP4Lhqx+7DDeAOxkgDW302dbQcyDvhsgFgOoyH22Knm
uapDGQYYFrxzhzgAu6zpAgMBAAGjggEkMIIBIDAJBgNVHRMEAjAAMB0GA1UdDgQW
BBSvkqnXNJsiMHDMVY1xVAWj5WDfvjCB0QYDVR0jBIHJMIHGgBSYKHQmnogRHUBv
k1XZWmPvf/N4LqGBoqSBnzCBnDELMAkGA1UEBhMCVEgxEzARBgNVBAgMCkNoaWFu
ZyBSYWkxDDAKBgNVBAcMA1BhbjEPMA0GA1UECgwGVEgtVlBOMRswGQYDVQQLDBJQ
YW5uYXdpdCBOYXJlZWRlY2gxFjAUBgNVBAMMDXRoLXZwbi5pbi5uZXQxJDAiBgkq
hkiG9w0BCQEWFXN1cHBvcnRAdGgtdnBuLmluLm5ldIIJAPmnobGw0ywUMBMGA1Ud
JQQMMAoGCCsGAQUFBwMCMAsGA1UdDwQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAQEA
U6ffsSztFfA+bEAAcNymP9Ohkd+uld9qrPpNL2rynowcEt4KpnV2wk6Aql02QOhF
iHnoDgpbzOC4wF0Ad2L9yw48iX6AajLaHrnPopePeuxGNCvijKk6BL2nrOi5Mb33
KM5Sv7lKhOc061Zfs9mpX/nNOdZXsyRGcmP8f4htA6wLPzDQZ/0IXZD1ChlYy1hi
+moGBocxTxvuzYiQZ/Wt8cwY1JBj1cW/JjcPfBeQ/uVkKuSimm3VISkjultkb4hF
ibuOD+k4UI6TFN/ZRWqG+KmV82bZUvoCLsiWVZqeB3mRhp6WnBLt1F1s38R1S4o+
QXskorPwRFLN48Hk1aFc4A==
-----END CERTIFICATE-----
EOF
}

start_services() {
    echo "Starting SHANVPN"
    apt update
    sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v4 boolean true"
    sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v6 boolean true"
    apt -y install iptables-persistent
    iptables -t nat -A PREROUTING -i $(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1) -p udp --dport 10000:65000 -j DNAT --to-destination $UDP_PORT
    ip6tables -t nat -A PREROUTING -i $(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1) -p udp --dport 10000:65000 -j DNAT --to-destination $UDP_PORT
    sysctl net.ipv4.conf.all.rp_filter=0
    sysctl net.ipv4.conf.$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1).rp_filter=0
    echo "net.ipv4.ip_forward = 1
    net.ipv4.conf.all.rp_filter=0
    net.ipv4.conf.$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1).rp_filter=0" > /etc/sysctl.conf
    sysctl -p
    sudo iptables-save > /etc/iptables/rules.v4
    sudo ip6tables-save > /etc/iptables/rules.v6
    systemctl enable hysteria-server.service
    systemctl start hysteria-server.service
}

main() {
    parse_arguments "$@"
    check_permission
    check_environment
    check_hysteria_user "hysteria"
    check_hysteria_homedir "/var/lib/$HYSTERIA_USER"
    case "$OPERATION" in
        "install")
            setup_db
            perform_install
            ;;
        "remove")
            perform_remove
            ;;
        *)
            error "Unknown operation '$OPERATION'."
            ;;
    esac
}

main "$@"
