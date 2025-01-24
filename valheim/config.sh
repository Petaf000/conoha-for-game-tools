#!/bin/bash
# Copyright (C) 2023 shinya-blogger https://github.com/shinya-blogger
# Licensed under the MIT License. See https://github.com/shinya-blogger/conoha-for-game-tools/blob/main/LICENSE

declare -r SYSTEMD_FILE="/etc/systemd/system/valheim_server.service"
declare -r SYSTEMD_DROPIN_DIR="/etc/systemd/system/valheim_server.service.d"
declare -r SYSTEMD_DROPIN_FILE="$SYSTEMD_DROPIN_DIR/override.conf"

declare -r VALHEIM_SERVER_DIR="/opt/valheim_server"
declare -r VALHEIM_SERVER_START_FILE="$VALHEIM_SERVER_DIR/gmovps_start_valheim_server.sh"
declare -r VALHEIM_SERVER_CONFIG_DIR="/home/valheim/.config/unity3d/IronGate/Valheim"
declare -r VALHEIM_SERVER_ADMIN_FILE="$VALHEIM_SERVER_CONFIG_DIR/adminlist.txt"
declare -r VALHEIM_SERVER_WORLD_DIR="$VALHEIM_SERVER_CONFIG_DIR/worlds_local"

declare -r STARTUP_VANNILA_FILE="$VALHEIM_SERVER_DIR/gmovps_start_valheim_server.sh"
declare -r STARTUP_BEPINEX_FILE="$VALHEIM_SERVER_DIR/gmovps_start_valheim_server_bepinex.sh"
declare -r DEFAULT_STARTUP_BEPINEX_FILE="$VALHEIM_SERVER_DIR/start_server_bepinex.sh"

declare -r TEMP_BEPINEX_FILE="/tmp/$$.bepinex.zip"

config_updated=false

function die() {
    local message="$1"
    echo "ERROR: $1"
    exit 1
}

function check_conoha_for_game() {
    if [ ! -d "$VALHEIM_SERVER_DIR" ] && [ ! -f "$STARTUP_VANNILA_FILE" ]; then
        die "This server is not a Valheim Server by ConoHa for GAME."
    fi
}

function check_bepinex_installed() {
    if [ -f "$STARTUP_BEPINEX_FILE" ]; then
        return 1
    else
        return 0
    fi
}

function install_package() {
    local pkg=$1
    if ! dpkg -l | grep -q "$pkg"; then
		echo "Installing library ..."
		apt-get -qq update && apt-get -qq install "$pkg"
	fi
}

function update_server_config() {
    param="$1"
    value="$2"
    valuetype="$3"

    if [ "$valuetype" == "string" ]; then
        value="\"$value\""
    fi

    files=("$STARTUP_VANNILA_FILE")
    if [ -f "$STARTUP_BEPINEX_FILE" ]; then
        files+=("$STARTUP_BEPINEX_FILE")
    fi

    for file in "${files[@]}"; do
        if grep -q -E "^[^#]+\/valheim_server.x86_64.* $param " "$file"; then
            sed -i -E "s/^([^#]+\/valheim_server.x86_64.* $param +)(\"[^\"]*\"|[^\" ]+)/\\1$value/" "$file"
        else
            sed -i -E "s/^([^#]+\/valheim_server.x86_64.*)$/\\1 $param $value/" "$file"
        fi
    done

    config_updated=true
}

function print_current_server_config() {
    param="$1"

    DEFULT_SERVER_CONFIG="./valheim_server.x86_64 -name \"Dedicated\" -world \"Valheim_World\" -public 1 -saveinterval 1800"
    STARTUP_SERVER_CONFIG=$(grep -E "/valheim_server.x86_64 " "$STARTUP_VANNILA_FILE" | grep -v -E "^#")

    line=$(echo -e -n "$DEFULT_SERVER_CONFIG\n$STARTUP_SERVER_CONFIG" | grep -E " $param " | tail -1)
    value=$(echo "$line" | sed -E "s/^.+ $param +(\"([^\"]*)\"|([^\" ]+)).*$/\\2\\3/")

    echo -n $value
}

function change_hostname() {
    echo
    current_val=$(print_current_server_config "-name")
    echo "Current Server Hostname: $current_val"

    while true; do
        read -p "Input Server Hostname: " hostname
        if [ -z "$hostname" ]; then
            break
        else
            update_server_config "-name" "$hostname" "string"
            break
        fi
    done
}

function change_password() {
    echo
    current_val=$(print_current_server_config "-password")
    echo "Current Password: $current_val"

    while true; do
        read -p "Input Password: " password
        if [ -z "$password" ]; then
            break
        else
            update_server_config "-password" "$password" "string"
            break
        fi
    done
}

function change_world() {
    echo 
    echo "Saved Worlds:"
    find "$VALHEIM_SERVER_WORLD_DIR" -type f -name "*.db" -a ! -name "*_backup_auto-*" -printf '%f\n' | sort | sed 's/\.db$//'

    echo
    current_val=$(print_current_server_config "-world")
    echo "Current World Name: $current_val"

    while true; do
        read -p "Input World Name: " world
        if [ -z "$world" ]; then
            break
        else
            update_server_config "-world" "$world" "string"
            break
        fi
    done
}

function add_admin() {
    echo
    echo "Current Admin Players:"
    grep -E -v "^\/\/" "$VALHEIM_SERVER_ADMIN_FILE"

    while true; do
        read -p "Input Admin Player's SteamId64: " admin
        if [ -z "$admin" ]; then
            break
        elif grep -q -E "^$admin$" "$VALHEIM_SERVER_ADMIN_FILE"; then
            echo "Already registered as admin player."    
            break
        else 
            echo "$admin" >> "$VALHEIM_SERVER_ADMIN_FILE"
            break
        fi
    done
}

function download_bepinex() {
    install_package libxml2-utils
    bepinex_url=$(curl -so- https://thunderstore.io/c/valheim/p/denikson/BepInExPack_Valheim/ \
        | xmllint --xpath '//a[contains(@href,"https://thunderstore.io/package/download/denikson/BepInExPack_Valheim/5.4.2202/")]/@href'  --html - 2> /dev/null \
        | grep 'href=' \
        | head -1 \
        | sed 's/[^"]*"\([^"]*\)"[^"]*/\1/g' )
    curl -sSL -o "$TEMP_BEPINEX_FILE" "$bepinex_url"
}

function extract_bepinex() {
    local temp_dir=/tmp/$$.unzip
    
    install_package unzip

    unzip -qq -o "$TEMP_BEPINEX_FILE" -d "$temp_dir"
    rsync -a --remove-source-files $temp_dir/BepInExPack_Valheim/ "$VALHEIM_SERVER_DIR/"
    chown -R valheim:valheim "$VALHEIM_SERVER_DIR/"

    rm -Rf "$temp_dir"
    rm -f "$TEMP_BEPINEX_FILE"
}

function create_startup_script_for_bepinex() {
    line=$(grep -E "/valheim_server.x86_64 " "$STARTUP_VANNILA_FILE" | grep -v -E "^#")

    line_number=$(grep -n -E "/valheim_server.x86_64 " "$DEFAULT_STARTUP_BEPINEX_FILE" | grep -v -E "^#" | cut -d : -f 1)
    head_lines=$((line_number - 1))
    tail_lines=$((line_number + 1))
    {
        head -n $head_lines $DEFAULT_STARTUP_BEPINEX_FILE;
        echo $line;
        tail -n +$tail_lines $DEFAULT_STARTUP_BEPINEX_FILE;
    } > $STARTUP_BEPINEX_FILE

    chmod +x $STARTUP_BEPINEX_FILE
    chown valheim:valheim $STARTUP_BEPINEX_FILE

    config_updated=true
}

function delete_startup_script_for_bepinex() {
    rm -f $STARTUP_BEPINEX_FILE
}

function create_default_systemd_dropin() {
    mkdir -p "$SYSTEMD_DROPIN_DIR"

    if [ ! -f "$SYSTEMD_DROPIN_FILE" ]; then
        echo "[Service]" > $SYSTEMD_DROPIN_FILE
    fi
}

function update_systemd_config_for_bepinex() {
    create_default_systemd_dropin
    sed -i '/^ExecStart=/d' "$SYSTEMD_DROPIN_FILE"
    echo "ExecStart=" >> "$SYSTEMD_DROPIN_FILE"
    echo "ExecStart=$STARTUP_BEPINEX_FILE" >> "$SYSTEMD_DROPIN_FILE"
    systemctl daemon-reload
    config_updated=true
}

function update_systemd_config_for_vanilla() {
    create_default_systemd_dropin
    sed -i '/^ExecStart=/d' "$SYSTEMD_DROPIN_FILE"
    systemctl daemon-reload
    config_updated=true
}

function install_bepinex_core() {
    download_bepinex 
    extract_bepinex
    create_startup_script_for_bepinex
    update_systemd_config_for_bepinex
}

function uninstall_bepinex_core() {
    delete_startup_script_for_bepinex
    update_systemd_config_for_vanilla
}

function install_bepinex() {
    echo
    check_bepinex_installed
    installed=$?
    
    if [ "$installed" == 1 ]; then
        echo "BepInEx already installed"
    fi

    while true; do
        read -p "Install BepInEx? (y/n): " answer
        if [ -z "$answer" ]; then
            break
        elif [ "$answer" == "y" ]; then
            install_bepinex_core
            echo "Install completed."
            break
        elif [ "$answer" == "n" ]; then
            break
        fi
        echo "Invalid choice."
    done
}

function uninstall_bepinex() {
    echo
    check_bepinex_installed
    installed=$?
    
    if [ "$installed" == 0 ]; then
        echo "BepInEx is not installed."
        return
    fi

    while true; do
        read -p "Uninstall BepInEx? (y/n): " answer
        if [ -z "$answer" ]; then
            break
        elif [ "$answer" == "y" ]; then
            uninstall_bepinex_core
            echo "Uninstall completed."
            break
        elif [ "$answer" == "n" ]; then
            break
        fi
        echo "Invalid choice."
    done
}

function quit() {
    echo

    if [ "$config_updated" == "true" ]; then
        restart_server
    fi

    exit 0
}

function restart_server() {
    local yes_no

    read -p "Restart Server? (y/n): " yes_no

    if [ "$yes_no" == "y" ] || [ "$yes_no" == "Y" ]; then
        echo "Restarting Valheim Server ..."
        systemctl restart valheim_server
    fi
}

function main_menu() {
    echo "Valheim Server Configutation Tool for 'ConoHa for GAME'"

    while true; do
        echo
        echo "1. Change Server Hostname"
        echo "2. Change Password"
        echo "3. Change World"
        echo "4. Add Admin Player"
        echo "5. Install BepInEx"
        echo "6. Uninstall BepInEx"
        echo "q. Quit"
        read -p "Please enter your choice(1-6,q): " choice

        case $choice in
            1) change_hostname ;;
            2) change_password ;;
            3) change_world ;;
            4) add_admin ;;
            5) install_bepinex ;;
            6) uninstall_bepinex ;;
            q) quit ;;
            *) echo "Invalid choice. Please try again." ;;
        esac
    done
}

check_conoha_for_game
main_menu
