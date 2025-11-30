#!/bin/bash

# ----------------- Colors -----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ----------------- Constants -----------------
NETPLAN_FILE="/etc/netplan/dev-ir.yaml"
SERVICE_NAME="gvtunnel-connector.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
CONNECTOR_SCRIPT="/root/connector.sh"

# ----------------- Root check -----------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Fatal error:${NC} Please run this script with root privilege.\n"
    exit 1
fi

# ----------------- Helpers -----------------
install_jq() {
    if command -v jq &> /dev/null; then
        return
    fi

    if command -v apt-get &> /dev/null; then
        echo -e "${YELLOW}jq is not installed. Installing...${NC}"
        sleep 1
        apt-get update
        apt-get install -y jq
    else
        echo -e "${RED}Error:${NC} Unsupported package manager. Please install jq manually.\n"
        read -rp "Press any key to exit..."
        exit 1
    fi
}

netplan_setup() {
    if command -v netplan &> /dev/null; then
        return
    fi

    if command -v apt-get &> /dev/null; then
        echo -e "${YELLOW}netplan is not installed. Installing...${NC}"
        apt-get update
        apt-get install -y netplan.io && echo "netplan installed successfully." || echo "netplan installation failed."
    else
        echo -e "${RED}Error:${NC} netplan is not installed and automatic installation is only supported with apt-get.\n"
        exit 1
    fi
}

check_core_status() {
    if [ -f "$NETPLAN_FILE" ]; then
        echo "Installed"
    else
        echo "Not installed"
    fi
}

# Generate random ULA IPv6 prefix like fd16:a803:2234
generate_ipv6_prefix() {
    local part1 part2 part3
    part1=$(printf 'fd%02x' $((RANDOM % 256)))
    part2=$(printf '%04x' $((RANDOM % 65536)))
    part3=$(printf '%04x' $((RANDOM % 65536)))
    echo "${part1}:${part2}:${part3}"
}

get_tunnel_ipv6() {
    local ipv6=""

    if [ -f "$NETPLAN_FILE" ]; then
        ipv6=$(grep -E '^[[:space:]]*- .*::[0-9]+/64' "$NETPLAN_FILE" 2>/dev/null | awk '{print $2}' | cut -d'/' -f1)
    fi

    echo "$ipv6"
}

create_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GV Tunnel IPv6 Connector
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash $CONNECTOR_SCRIPT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME"
}

remove_service() {
    if systemctl is-enabled "$SERVICE_NAME" &> /dev/null; then
        systemctl disable --now "$SERVICE_NAME"
    else
        systemctl stop "$SERVICE_NAME" &> /dev/null || true
    fi

    [ -f "$SERVICE_FILE" ] && rm -f "$SERVICE_FILE"
    systemctl daemon-reload
}

ensure_systemd_networkd() {
    # اگر اصلاً یونیت تعریف نشده باشه، بی‌خیال میشیم
    if ! systemctl list-unit-files | grep -q '^systemd-networkd.service'; then
        echo -e "${YELLOW}systemd-networkd.service not found. Skipping networkd check.${NC}"
        return
    fi

    echo -e "${YELLOW}Ensuring systemd-networkd is unmasked and enabled...${NC}"

    systemctl unmask systemd-networkd.service 2>/dev/null || true

    systemctl enable --now systemd-networkd.service 2>/dev/null || {
        echo -e "${RED}Failed to enable/start systemd-networkd.${NC}"
        return 1
    }

    echo -e "${GREEN}systemd-networkd is active and enabled.${NC}"
}

apply_netplan_safe() {
    netplan_setup
    ensure_systemd_networkd

    echo -e "${YELLOW}Applying netplan...${NC}"
    if ! netplan apply 2>/tmp/netplan_error.log; then
        echo -e "${RED}netplan apply failed!${NC}"
        echo "------ netplan error output ------"
        cat /tmp/netplan_error.log
        echo "----------------------------------"
        read -rp "Press Enter to return to menu..."
        return 1
    fi
}

gv_menu() {
    clear

    local SERVER_IP SERVER_COUNTRY SERVER_ISP IP_INFO
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY="Unknown"
    SERVER_ISP="Unknown"

    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        IP_INFO=$(curl -sS "http://ip-api.com/json/$SERVER_IP" || true)
        if [ -n "$IP_INFO" ]; then
            SERVER_COUNTRY=$(echo "$IP_INFO" | jq -r '.country // "Unknown"')
            SERVER_ISP=$(echo "$IP_INFO" | jq -r '.isp // "Unknown"')
        fi
    fi

    local GV_CORE TUN_IPV6 core_color
    GV_CORE=$(check_core_status)
    TUN_IPV6=$(get_tunnel_ipv6)

    if [ "$GV_CORE" = "Installed" ]; then
        core_color="$GREEN"
    else
        core_color="$RED"
    fi

    echo "+-------------------------------------------------------------------------+"
    echo "|                                                                         |"
    echo "|  ██████  ██    ██ ████████ ██    ██ ███    ██ ███    ██ ███████ ██      |"   
    echo "| ██       ██    ██    ██    ██    ██ ████   ██ ████   ██ ██      ██      |"
    echo "| ██   ███ ██    ██    ██    ██    ██ ██ ██  ██ ██ ██  ██ █████   ██      |"
    echo "| ██    ██  ██  ██     ██    ██    ██ ██  ██ ██ ██  ██ ██ ██      ██      |"
    echo "|  ██████    ████      ██     ██████  ██   ████ ██   ████ ███████ ███████ |"
    echo "|                                                       version :  2.6.1  |"
    echo "+-------------------------------------------------------------------------+"
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    if [ -n "$TUN_IPV6" ]; then
        echo -e "|${GREEN}Tunnel IPv6       |${NC} $TUN_IPV6"
    fi
    echo -e "|${GREEN}Server Tunnel     |${NC} ${core_color}${GV_CORE}${NC}"
    echo "+-------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-------------------------------------------------------------------------+"
    echo -e "$1"
    echo "+-------------------------------------------------------------------------+"
    echo -e "${NC}"
}

check_service_status() {
    gv_menu "| 3  - Check Service Status\n"

    echo "----- $SERVICE_NAME status -----"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}Service is ACTIVE${NC}"
    else
        echo -e "${RED}Service is INACTIVE or not installed${NC}"
    fi
    echo
    systemctl --no-pager --full status "$SERVICE_NAME" 2>/dev/null | sed -n '1,15p'
    echo
    read -rp "Press Enter to go back to menu..."
}

# Unified setup for IRAN / Kharej
setup_tunnel() {
    local role="$1"
    local iran_ip kharej_ip ipv6_prefix
    local local_ip remote_ip
    local local_suffix remote_suffix
    local side_label side_text other_side_text

    case "$role" in
        iran)
            side_label="IRAN"
            local_suffix="1"
            remote_suffix="2"
            read -rp "Enter IRAN IP                 : " iran_ip
            read -rp "Enter Kharej IP               : " kharej_ip
            local_ip="$iran_ip"
            remote_ip="$kharej_ip"
            side_text="IRAN Tunnel IPv6"
            other_side_text="Use this prefix on the KHAREJ side as well"
            ;;
        kharej)
            side_label="Kharej"
            local_suffix="2"
            remote_suffix="1"
            read -rp "Enter IRAN IP                 : " iran_ip
            read -rp "Enter Kharej IP               : " kharej_ip
            local_ip="$kharej_ip"
            remote_ip="$iran_ip"
            side_text="Kharej Tunnel IPv6"
            other_side_text="Use the same prefix on the IRAN side"
            ;;
        *)
            echo "Unknown role: $role"
            return 1
            ;;
    esac

    read -rp "Enter IPv6 Local Prefix (blank = auto): " ipv6_prefix
    if [ -z "$ipv6_prefix" ]; then
        ipv6_prefix=$(generate_ipv6_prefix)
        echo -e "${YELLOW}Auto-generated IPv6 prefix:${NC} $ipv6_prefix"
    fi

    cat > "$NETPLAN_FILE" <<EOL
network:
  version: 2
  tunnels:
    tunnel0858:
      mode: sit
      local: $local_ip
      remote: $remote_ip
      addresses:
        - ${ipv6_prefix}::${local_suffix}/64
EOL

    apply_netplan_safe || return 1

    cat > "$CONNECTOR_SCRIPT" <<EOL
#!/bin/bash
while true; do
    ping -6 -c 3 ${ipv6_prefix}::${remote_suffix}
    sleep 5
done
EOL

    chmod +x "$CONNECTOR_SCRIPT"
    create_service

    local final_ipv6="${ipv6_prefix}::${local_suffix}"
    echo
    echo "Your job is great..."
    echo "####################################"
    printf "# %-28s #\n" "$side_text :"
    printf "#  %s\n" " $final_ipv6"
    echo "####################################"
    echo
    echo "$other_side_text: $ipv6_prefix"
    echo
    read -rp "Press Enter to return to menu..."
}

install_tunnel() {
    gv_menu "| 1  - IRAN\n| 2  - Kharej\n| 0  - Back"

    read -rp "Enter option number: " setup
    case $setup in
        1) setup_tunnel "iran" ;;
        2) setup_tunnel "kharej" ;;
        0) return ;;
        *) echo "Not valid" ;;
    esac
}

uninstall_tunnel() {
    echo -e "${GREEN}Uninstalling GVTUNNEL in 3 seconds...${NC}"
    sleep 1 && echo -e "${GREEN}2...${NC}"
    sleep 1 && echo -e "${GREEN}1...${NC}"
    sleep 1

    remove_service
    [ -f "$NETPLAN_FILE" ] && rm -f "$NETPLAN_FILE"
    [ -f "$CONNECTOR_SCRIPT" ] && rm -f "$CONNECTOR_SCRIPT"

    apply_netplan_safe || true
    clear
    echo 'GVTUNNEL Uninstalled :('
}

loader() {
    gv_menu "| 1  - Config Tunnel\n| 2  - Uninstall\n| 3  - Check Service\n| 0  - Exit"

    read -rp "Enter option number: " choice
    case $choice in
        1) install_tunnel ;;
        2) uninstall_tunnel ;;
        3) check_service_status ;;
        0)
            echo -e "${GREEN}Exiting program...${NC}"
            exit 0
            ;;
        *)
            echo "Not valid"
            ;;
    esac
}

init() {
    install_jq

    # Ensure iproute2/ip command exists
    if ! command -v ip &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            echo -e "${YELLOW}iproute2 is not installed. Installing...${NC}"
            apt-get update
            apt-get install -y iproute2
        else
            echo -e "${YELLOW}Warning:${NC} 'ip' command not found and automatic installation is only supported with apt-get. Please install iproute2 manually."
        fi
    fi
}

# ---- main ----
init
while true; do
    loader
done
