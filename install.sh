#!/bin/bash

#add color for text
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
plain='\033[0m'
NC='\033[0m' # No Color


cur_dir=$(pwd)
# check root
# [[ $EUID -ne 0 ]] && echo -e "${RED}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

install_jq() {
    if ! command -v jq &> /dev/null; then
        # Check if the system is using apt package manager
        if command -v apt-get &> /dev/null; then
            echo -e "${RED}jq is not installed  Installing   ${NC}"
            sleep 1
            sudo apt-get update
            sudo apt-get install -y jq
        else
            echo -e "${RED}Error: Unsupported package manager  Please install jq manually ${NC}\n"
            read -p "Press any key to continue   "
            exit 1
        fi
    fi
}


loader(){

    apt update && apt upgrade -y
    sudo apt-get install iproute2
    # run_screen
    # install_jq

    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')

    # Fetch server country using ip-api com
    SERVER_COUNTRY=$(curl -sS "http://ip-api com/yaml/$SERVER_IP" | jq -r ' country')

    # Fetch server isp using ip-api com 
    SERVER_ISP=$(curl -sS "http://ip-api com/yaml/$SERVER_IP" | jq -r ' isp')

    GV_CORE=$(check_core_status)
    WATER_TUNNEL=$(check_tunnel_status)

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

    clear
    echo "+-------------------------------------------------------------------------------+"
    echo "|                                                                               |" 
    echo "|   _____ __      __ _______  _    _  _   _  _   _  ______  _                   |"
    echo "|  / ____|\ \    / /|__   __|| |  | || \ | || \ | ||  ____|| |                  |"
    echo "| | |  __  \ \  / /    | |   | |  | ||  \| ||  \| || |__   | |                  |"
    echo "| | | |_ |  \ \/ /     | |   | |  | ||     ||     ||  __|  | |                  |"
    echo "| | |__| |   \  /      | |   | |__| || |\  || |\  || |____ | |____  ( V2.0 )    |"
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

    case $setup in
    1)
        iran_setup
        ;;  
    2)
        kharej_setup
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
    
    read -p "Enter IRAN IP    : " iran_ip
    read -p "Enter Kharej IP  : " kharej_ip
    read -p "Enter IPv6 Local : " ipv6_local
    
    read -p "Enter Kharej Ports ( comma seperate ) : " kharej_port

cat <<EOL > etc/netplan/dev-ir.yaml
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

    sudo netplan apply

    screen -dmS ping $ipv6_local::2

    clear

    echo "Your job is greate..."


}

kharej_setup(){
    
    read -p "Enter IRAN IP    : " iran_ip
    read -p "Enter Kharej IP  : " kharej_ip
    read -p "Enter IPv6 Local : " ipv6_local
    
    read -p "Enter Kharej Ports ( comma seperate ) : " kharej_port

cat <<EOL > etc/netplan/dev-ir.yaml
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

    sudo netplan apply

    screen -dmS ping $ipv6_local::1

    clear

    echo "Your job is greate..."


}

run_screen(){
#!/bin/bash

# Check if screen is installed
if ! command -v screen &> /dev/null
then
    echo "Screen is not installed. Installing..."
    
    # Check the Linux distribution to use the correct package manager
    if [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        sudo yum install screen -y
    elif [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install screen -y
    else
        echo "Unsupported Linux distribution. Please install screen manually."
        exit 1
    fi
    
    # Verify installation
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
    local file_path="etc/netplan/dev-ir.yaml"
    local status

    if [ -f "$file_path" ]; then
        status="${GREEN}Installed"${NC}
    else
        status=${RED}"Not installed"${NC}
    fi

    echo "$status"
}

unistall(){

    echo $'\e[32mUninstalling WaterWall in 3 seconds... \e[0m' && sleep 1 && echo $'\e[32m2... \e[0m' && sleep 1 && echo $'\e[32m1... \e[0m' && sleep 1 && {
    rm /etc/netplan/dev-ir.yaml
    clear
    echo 'GVTUNNEL Unistalled :(';
    }
    loader
}

loader