#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Fatal error:${NC} Please run this script with root privilege.\n"
    exit 1
fi

install_jq() {
    if ! command -v jq &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            echo -e "${YELLOW}jq is not installed. Installing...${NC}"
            sleep 1
            apt-get update
            apt-get install -y jq
        else
            echo -e "${RED}Error:${NC} Unsupported package manager. Please install jq manually.\n"
            read -p "Press any key to exit..."
            exit 1
        fi
    fi
}

netplan_setup() {
    if ! command -v netplan &> /dev/null; then
        apt-get update && apt-get install -y netplan.io && echo "netplan installed successfully." || echo "netplan installation failed."
    fi
}

check_core_status() {
    local file_path="/etc/netplan/dev-ir.yaml"
    local status

    if [ -f "$file_path" ]; then
        status="${GREEN}Installed${NC}"
    else
        status="${RED}Not installed${NC}"
    fi

    echo "$status"
}

create_service() {
    local service_file="/etc/systemd/system/gvtunnel-connector.service"

    cat > "$service_file" <<EOF
[Unit]
Description=GV Tunnel IPv6 Connector
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash /root/connector.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now gvtunnel-connector.service
}

remove_service() {
    local service_file="/etc/systemd/system/gvtunnel-connector.service"

    if systemctl is-enabled gvtunnel-connector.service &> /dev/null; then
        systemctl disable --now gvtunnel-connector.service
    else
        systemctl stop gvtunnel-connector.service &> /dev/null || true
    fi

    [ -f "$service_file" ] && rm -f "$service_file"
    systemctl daemon-reload
}

gv_menu() {
    clear

    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')

    # Fetch server country using ip-api.com
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')

    # Fetch server isp using ip-api.com
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

    GV_CORE=$(check_core_status)

    echo "+-------------------------------------------------------------------------------+"
    echo "|                                                                               |"
    echo "|   _____ __      __ _______  _    _  _   _  _   _  ______  _                   |"
    echo "|  / ____|\\ \\    / /|__   __|| |  | || \\ | || \\ | ||  ____|| |                  |"
    echo "| | |  __  \\ \\  / /    | |   | |  | ||  \\| ||  \\| || |__   | |                  |"
    echo "| | | |_ |  \\ \\/ /     | |   | |  | ||     ||     ||  __|  | |                  |"
    echo "| | |__| |   \\  /      | |   | |__| || |\\  || |\\  || |____ | |____  ( V2.3 )    |"
    echo "|  \\_____|    \\/       |_|    \\____/ |_| \\_||_| \\_||______||______|             |"
    echo "|                                                                               |"
    echo "+-------------------------------------------------------------------------------+"
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo -e "|${GREEN}Server Tunnel     |${NC} $GV_CORE"
    echo "+-------------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-------------------------------------------------------------------------------+"
    echo -e "$1"
    echo "+-------------------------------------------------------------------------------+"
    echo -e "\033[0m"
}

install_tunnel() {
    gv_menu "| 1  - IRAN\n| 2  - Kharej\n| 0  - Back"

    read -p "Enter option number: " setup

    case $setup in
        1) iran_setup ;;
        2) kharej_setup ;;
        0) return ;;
        *) echo "Not valid";;
    esac
}

iran_setup() {
    read -p "Enter IRAN IP    : " iran_ip
    read -p "Enter Kharej IP  : " kharej_ip
    read -p "Enter IPv6 Local : " ipv6_local

    cat > /etc/netplan/dev-ir.yaml <<EOL
network:
  version: 2
  tunnels:
    tunnel0858:
      mode: sit
      local: $iran_ip
      remote: $kharej_ip
      addresses:
        - $ipv6_local::1/64
EOL

    netplan_setup
    netplan apply

    cat > /root/connector.sh <<EOL
#!/bin/bash
while true; do
    ping -6 -c 3 $ipv6_local::2
    sleep 5
done
EOL

    chmod +x /root/connector.sh
    create_service

    echo "Your job is great..."
    echo "####################################"
    echo "# Your IPv6 :                      #"
    echo "#  $ipv6_local::1                  #"
    echo "####################################"
}

kharej_setup() {
    read -p "Enter IRAN IP    : " iran_ip
    read -p "Enter Kharej IP  : " kharej_ip
    read -p "Enter IPv6 Local : " ipv6_local

    cat > /etc/netplan/dev-ir.yaml <<EOL
network:
  version: 2
  tunnels:
    tunnel0858:
      mode: sit
      local: $kharej_ip
      remote: $iran_ip
      addresses:
        - $ipv6_local::2/64
EOL

    netplan_setup
    netplan apply

    cat > /root/connector.sh <<EOL
#!/bin/bash
while true; do
    ping -6 -c 3 $ipv6_local::1
    sleep 5
done
EOL

    chmod +x /root/connector.sh
    create_service

    echo "Your job is great..."
    echo "####################################"
    echo "# Your IPv6 :                      #"
    echo "#  $ipv6_local::2                  #"
    echo "####################################"
}

unistall() {
    echo -e "${GREEN}Uninstalling GVTUNNEL in 3 seconds...${NC}"
    sleep 1 && echo -e "${GREEN}2...${NC}"
    sleep 1 && echo -e "${GREEN}1...${NC}"
    sleep 1

    remove_service
    [ -f /etc/netplan/dev-ir.yaml ] && rm -f /etc/netplan/dev-ir.yaml
    [ -f /root/connector.sh ] && rm -f /root/connector.sh

    netplan apply || true
    clear
    echo 'GVTUNNEL Uninstalled :('
}

loader() {
    gv_menu "| 1  - Config Tunnel\n| 2  - Uninstall\n| 0  - Exit"

    read -p "Enter option number: " choice
    case $choice in
        1) install_tunnel ;;
        2) unistall ;;
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
    apt-get install -y iproute2
}

# ---- main ----
init
while true; do
    loader
done
