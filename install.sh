#!/bin/bash

# Add color for text
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
plain='\033[0m'
NC='\033[0m' # No Color

cur_dir=$(pwd)
# Check root
[[ $EUID -ne 0 ]] && echo -e "${RED}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

install_jq() {
    if ! command -v jq &> /dev/null; then
        # Check if the system is using apt package manager
        if command -v apt-get &> /dev/null; then
            echo -e "${RED}jq is not installed. Installing...${NC}"
            sleep 1
            sudo apt-get update
            sudo apt-get install -y jq
        else
            echo -e "${RED}Error: Unsupported package manager. Please install jq manually.${NC}\n"
            read -p "Press any key to continue..."
            exit 1
        fi
    fi
}

init(){
	install_jq
    sudo apt-get install iproute2
    run_screen
}

loader(){
	
    gv_menu "| 1  - Config Tunnel \n| 2  - Unistall\n| 0  - Exit"

    read -p "Enter option number: " choice
    case $choice in
    1)
        install_tunnel
        ;;  
    2)
        unistall
        ;;
    0)
        echo -e "${GREEN}Exiting program...${NC}"
        exit 0
        ;;
    *)
        echo "Not valid"
        ;;
    esac

}

gv_menu(){
	init
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
    echo "|  / ____|\ \    / /|__   __|| |  | || \ | || \ | ||  ____|| |                  |"
    echo "| | |  __  \ \  / /    | |   | |  | ||  \| ||  \| || |__   | |                  |"
    echo "| | | |_ |  \ \/ /     | |   | |  | ||     ||     ||  __|  | |                  |"
    echo "| | |__| |   \  /      | |   | |__| || |\  || |\  || |____ | |____  ( V3.2 )    |"
    echo "|  \_____|    \/       |_|    \____/ |_| \_||_| \_||______||______|             |"
    echo "|                                                                               |" 
    echo "+-------------------------------------------------------------------------------+"                                                                                                         
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo -e "|${GREEN}Server Tunnel     |${NC} $GV_CORE"
    echo "+--------------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+--------------------------------------------------------------------------------+"
    echo -e $1
    echo "+---------------------------------------------------------------------------------+"
    echo -e "\033[0m"
}

install_tunnel(){
    gv_menu "| 1  - IRAN \n| 2  - Kharej \n| 0  - Exit"

    read -p "Enter option number: " setup

    read -p "How many servers: " server_count

    case $setup in
    1)
        for ((i=1;i<=server_count;i++))
        do
            iran_setup $i
        done
        ;;  
    2)
        for ((i=1;i<=server_count;i++))
        do
            kharej_setup $i
        done
        ;;
    0)
        echo -e "${GREEN}Exiting program...${NC}"
        exit 0
        ;;
    *)
        echo "Not valid"
        ;;
    esac

}

iran_setup(){
    echo -e "${YELLOW}Setting up IRAN server $1${NC}"
    
    read -p "Enter IRAN IP    : " iran_ip
    read -p "Enter Kharej IP  : " kharej_ip
    read -p "Enter IPv6 Local : " ipv6_local
    
    cat <<EOL > /etc/netplan/mramini-$1.yaml
network:
  version: 2
  tunnels:
    tunnel0858-$1:
      mode: sit
      local: $iran_ip
      remote: $kharej_ip
      addresses:
        - $ipv6_local::1/64
EOL
    netplan_setup
    sudo netplan apply

cat <<EOL > /root/connectors-$1.sh
ping $ipv6_local::2
EOL

    chmod +x /root/connectors-$1.sh

    screen -dmS connectors_session_$1 bash -c "/root/connectors-$1.sh"

    echo "IRAN Server $1 setup complete."
    echo -e "####################################"
    echo -e "# Your IPv6 :                      #"
    echo -e "#  $ipv6_local::1                  #"
    echo -e "####################################"
}

kharej_setup(){
    echo -e "${YELLOW}Setting up Kharej server $1${NC}"
    
    read -p "Enter IRAN IP    : " iran_ip
    read -p "Enter Kharej IP  : " kharej_ip
    read -p "Enter IPv6 Local : " ipv6_local
    
    cat <<EOL > /etc/netplan/mramini-$1.yaml
network:
  version: 2
  tunnels:
    tunnel0858-$1:
      mode: sit
      local: $kharej_ip
      remote: $iran_ip
      addresses:
        - $ipv6_local::2/64
EOL
    netplan_setup
    sudo netplan apply

cat <<EOL > /root/connectors-$1.sh
ping $ipv6_local::1
EOL

    chmod +x /root/connectors-$1.sh

    screen -dmS connectors_session_$1 bash -c "/root/connectors-$1.sh"

    echo "Kharej Server $1 setup complete."
    echo -e "####################################"
    echo -e "# Your IPv6 :                      #"
    echo -e "#  $ipv6_local::2                  #"
    echo -e "####################################"
}

# Add service creation function
create_ping_service() {
    cat <<EOL > /etc/systemd/system/ping-monitor.service
[Unit]
Description=Ping Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/root/ping_monitor.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable ping-monitor.service
    systemctl start ping-monitor.service

    echo -e "${GREEN}Ping monitor service has been created and started.${NC}"
}

create_ping_monitor_script(){
    cat <<EOL > /root/ping_monitor.sh
#!/bin/bash

while true; do
  for file in /root/connectors-*.sh; do
    echo "Running \$file"
    bash \$file &
    sleep 5
  done
  sleep 5
done
EOL

    chmod +x /root/ping_monitor.sh
}

run_screen(){
#!/bin/bash

# Check if screen is installed
if ! command -v screen &> /dev/null
then
    echo "Screen is not installed. Installing..."
    
    if [ -f /etc/redhat-release ]; then
        sudo yum install screen -y
    elif [ -f /etc/debian_version ]; then
        sudo apt-get update
        sudo apt-get install screen -y
    else
        echo "Unsupported Linux distribution. Please install screen manually."
        exit 1
    fi

    if ! command -v screen &> /dev/null
    then
        echo "Failed to install screen. Please install manually."
        exit 1
    else
        echo "Screen has been successfully installed."
    fi
else
    echo "Screen is already installed."
fi
}

check_core_status() {
    local file_path="/etc/netplan/mramini-1.yaml"
    local status

    if [ -f "$file_path" ]; then
        status="${GREEN}Installed"${NC}
    else
        status=${RED}"Not installed"${NC}
    fi

    echo "$status"
}

netplan_setup(){
    command -v netplan &> /dev/null || { 
        sudo apt update && sudo apt install -y netplan.io && echo "netplan با موفقیت نصب شد." || echo "نصب netplan با خطا مواجه شد."; 
    }
}

unistall(){
    echo $'\e[32mUninstalling GVTUNNEL in 3 seconds... \e[0m' && sleep 1 && echo $'\e[32m2... \e[0m' && sleep 1 && echo $'\e[32m1... \e[0m' && sleep 1 && {
    rm /etc/netplan/mramini*.yaml
    rm /root/connectors-*.sh
    pkill screen
    clear
    echo 'GVTUNNEL Uninstalled :(';
    systemctl stop ping-monitor.service
    systemctl disable ping-monitor.service
    rm /etc/systemd/system/ping-monitor.service
    rm /root/ping_monitor.sh
    }
    loader
}

loader
