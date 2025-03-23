#!/bin/sh
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
[ -f "$USERDATA_PATH/$PAK_NAME/debug" ] && set -x

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

echo "$0" "$@"
cd "$PAK_DIR" || exit 1
mkdir -p "$USERDATA_PATH/$PAK_NAME"

architecture=arm
if uname -m | grep -q '64'; then
    architecture=arm64
fi

export HOME="$USERDATA_PATH/$PAK_NAME"
export LD_LIBRARY_PATH="$PAK_DIR/lib:$LD_LIBRARY_PATH"
export PATH="$PAK_DIR/bin/$architecture:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"

main_screen() {
    minui_list_file="/tmp/minui-list"
    rm -f "$minui_list_file"
    touch "$minui_list_file"

    start_on_boot=false
    if will_start_on_boot; then
        start_on_boot=true
    fi

    echo "Enabled: false" >>"$minui_list_file"
    echo "Start on boot: $start_on_boot" >>"$minui_list_file"
    echo "Enable" >>"$minui_list_file"
    echo "Toggle start on boot" >>"$minui_list_file"

    ip_address="N/A"
    if wifi-enabled; then
        echo "Enabled: true" >"$minui_list_file"
        echo "Start on boot: $start_on_boot" >>"$minui_list_file"
        echo "Disable" >>"$minui_list_file"
        echo "Connect to network" >>"$minui_list_file"
        echo "Toggle start on boot" >>"$minui_list_file"
    fi

    ssid="N/A"
    ip_address="N/A"
    enabled="$(cat /sys/class/net/wlan0/operstate)"
    if [ "$enabled" = "up" ]; then
        ssid=""
        ip_address=""

        count=0
        while true; do
            count=$((count + 1))
            if [ "$count" -gt 5 ]; then
                break
            fi

            ssid="$(iw dev wlan0 link | grep SSID: | cut -d':' -f2- | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')"
            ip_address="$(ip addr show wlan0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)"
            if [ -n "$ip_address" ] && [ -n "$ssid" ]; then
                break
            fi
            sleep 1
        done

        if [ -z "$ssid" ]; then
            ssid="N/A"
        fi
        if [ -z "$ip_address" ]; then
            ip_address="N/A"
        fi

        if [ "$ssid" != "N/A" ] && [ "$ip_address" != "N/A" ]; then
            echo "Enabled: true" >"$minui_list_file"
            echo "Start on boot: $start_on_boot" >>"$minui_list_file"
            echo "SSID: $ssid" >>"$minui_list_file"
            if [ "$ip_address" = "N/A" ]; then
                echo "IP: N/A" >>"$minui_list_file"
                echo "Refresh connection" >>"$minui_list_file"
            else
                echo "IP: $ip_address" >>"$minui_list_file"
            fi
            echo "Disable" >>"$minui_list_file"
            echo "Connect to network" >>"$minui_list_file"
            echo "Toggle start on boot" >>"$minui_list_file"
        fi
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    minui-list --file "$minui_list_file" --format text --header "Wifi Configuration"
}

networks_screen() {
    show_message "Scanning for networks..." 2
    DELAY=30

    minui_list_file="/tmp/minui-list"
    rm -f "$minui_list_file"
    touch "$minui_list_file"
    for i in $(seq 1 "$DELAY"); do
        iw dev wlan0 scan | grep SSID: | cut -d':' -f2- | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' | sort >>"$minui_list_file"
        if [ -s "$minui_list_file" ]; then
            break
        fi
        sleep 1
    done

    killall minui-presenter >/dev/null 2>&1 || true
    minui-list --file "$minui_list_file" --format text --header "Wifi Networks"
}

password_screen() {
    SSID="$1"

    touch "$SDCARD_PATH/wifi.txt"

    initial_password=""
    if grep -q "^$SSID:" "$SDCARD_PATH/wifi.txt" 2>/dev/null; then
        initial_password="$(grep "^$SSID:" "$SDCARD_PATH/wifi.txt" | cut -d':' -f2- | xargs)"
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    password="$(minui-keyboard --header "Enter Password" --initial-value "$initial_password")"
    exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        return 2
    fi
    if [ "$exit_code" -eq 3 ]; then
        return 3
    fi
    if [ "$exit_code" -ne 0 ]; then
        show_message "Error entering password" 2
        return 1
    fi

    if [ -z "$password" ]; then
        show_message "Password cannot be empty" 2
        return 1
    fi

    touch "$SDCARD_PATH/wifi.txt"

    if grep -q "^$SSID:" "$SDCARD_PATH/wifi.txt" 2>/dev/null; then
        sed -i "/^$SSID:/d" "$SDCARD_PATH/wifi.txt"
    fi

    echo "$SSID:$password" >"$SDCARD_PATH/wifi.txt.tmp"
    cat "$SDCARD_PATH/wifi.txt" >>"$SDCARD_PATH/wifi.txt.tmp"
    mv "$SDCARD_PATH/wifi.txt.tmp" "$SDCARD_PATH/wifi.txt"
    return 0
}

show_message() {
    message="$1"
    seconds="$2"

    if [ -z "$seconds" ]; then
        seconds="forever"
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$message" 1>&2
    if [ "$seconds" = "forever" ]; then
        minui-presenter --message "$message" --timeout -1 &
    else
        minui-presenter --message "$message" --timeout "$seconds"
    fi
}

disable_start_on_boot() {
    sed -i "/${PAK_NAME}.pak-on-boot/d" "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    sync
    return 0
}

enable_start_on_boot() {
    if [ ! -f "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh" ]; then
        echo '#!/bin/sh' >"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
        echo '' >>"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    fi

    echo "test -f \"\$SDCARD_PATH/Tools/\$PLATFORM/$PAK_NAME.pak/bin/on-boot\" && \"\$SDCARD_PATH/Tools/\$PLATFORM/$PAK_NAME.pak/bin/on-boot\" # ${PAK_NAME}.pak-on-boot" >>"$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    chmod +x "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh"
    sync
    return 0
}

will_start_on_boot() {
    if grep -q "${PAK_NAME}.pak-on-boot" "$SDCARD_PATH/.userdata/$PLATFORM/auto.sh" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

write_config() {
    echo "Generating wpa_supplicant.conf..."
    cp "$PAK_DIR/res/wpa_supplicant.conf.tmpl" "$PAK_DIR/res/wpa_supplicant.conf"
    echo "Generating netplan.yaml..."
    cp "$PAK_DIR/res/netplan.yaml.tmpl" "$PAK_DIR/res/netplan.yaml"

    if [ ! -f "$SDCARD_PATH/wifi.txt" ] && [ -f "$PAK_DIR/wifi.txt" ]; then
        mv "$PAK_DIR/wifi.txt" "$SDCARD_PATH/wifi.txt"
    fi

    touch "$SDCARD_PATH/wifi.txt"
    sed -i '/^$/d' "$SDCARD_PATH/wifi.txt"
    # exit non-zero if no wifi.txt file or empty
    if [ ! -s "$SDCARD_PATH/wifi.txt" ]; then
        show_message "No credentials found in wifi.txt" 2
        return 1
    fi

    has_passwords=false
    priority_used=false
    echo "" >>"$SDCARD_PATH/wifi.txt"
    while read -r line; do
        line="$(echo "$line" | xargs)"
        if [ -z "$line" ]; then
            continue
        fi

        # skip if line starts with a comment
        if echo "$line" | grep -q "^#"; then
            continue
        fi

        # skip if line is not in the format "ssid:psk"
        if ! echo "$line" | grep -q ":"; then
            continue
        fi

        ssid="$(echo "$line" | cut -d: -f1 | xargs)"
        psk="$(echo "$line" | cut -d: -f2- | xargs)"
        if [ -z "$ssid" ] || [ -z "$psk" ]; then
            continue
        fi

        has_passwords=true

        {
            echo "network={"
            echo "    ssid=\"$ssid\""
            echo "    psk=\"$psk\""
            if [ "$priority_used" = false ]; then
                echo "    priority=1"
                priority_used=true
            fi
            echo "}"
        } >>"$PAK_DIR/res/wpa_supplicant.conf"
        {
            echo "                \"$ssid\":"
            echo "                    password: \"$psk\""
        } >>"$PAK_DIR/res/netplan.yaml"
    done <"$SDCARD_PATH/wifi.txt"

    if [ "$PLATFORM" = "rg35xxplus" ]; then
        cp "$PAK_DIR/res/wpa_supplicant.conf" /etc/wpa_supplicant/wpa_supplicant.conf
        cp "$PAK_DIR/res/netplan.yaml" /etc/netplan/01-netcfg.yaml
        if [ "$has_passwords" = false ]; then
            rm -f /etc/netplan/01-netcfg.yaml
        fi
    elif [ "$PLATFORM" = "tg5040" ]; then
        cp "$PAK_DIR/res/wpa_supplicant.conf" /etc/wifi/wpa_supplicant.conf
    else
        show_message "$PLATFORM is not a supported platform" 2
        return 1
    fi
}

wifi_off() {
    echo "Preparing to toggle wifi off..."
    if [ "$PLATFORM" = "tg5040" ]; then
        SYSTEM_JSON_PATH="/mnt/UDISK/system.json"
        [ ! -f "$SYSTEM_JSON_PATH" ] && echo '{"wifi": 0}' >"$SYSTEM_JSON_PATH"
        [ ! -s "$SYSTEM_JSON_PATH" ] && echo '{"wifi": 0}' >"$SYSTEM_JSON_PATH"

        if [ -x /usr/trimui/bin/systemval ]; then
            /usr/trimui/bin/systemval wifi 0
        else
            chmod +x "$PAK_DIR/bin/$architecture/jq"
            jq '.wifi = 0' "$SYSTEM_JSON_PATH" >"/tmp/system.json.tmp"
            mv "/tmp/system.json.tmp" "$SYSTEM_JSON_PATH"
        fi
    fi

    if pgrep wpa_supplicant; then
        echo "Stopping wpa_supplicant..."
        /etc/init.d/wpa_supplicant stop || true
        systemctl stop wpa_supplicant || true
        killall -9 wpa_supplicant 2>/dev/null || true
    fi

    status="$(cat /sys/class/net/wlan0/flags)"
    if [ "$status" = "0x1003" ]; then
        echo "Marking wlan0 interface down..."
        ifconfig wlan0 down || true
    fi

    if [ ! -f /sys/class/rfkill/rfkill0/state ]; then
        echo "Blocking wireless..."
        rfkill block wifi || true
    fi

    cp "$PAK_DIR/res/wpa_supplicant.conf.tmpl" "$PAK_DIR/res/wpa_supplicant.conf"
    if [ "$PLATFORM" = "rg35xxplus" ]; then
        rm -f /etc/netplan/01-netcfg.yaml
        netplan apply
        systemctl stop systemd-networkd || true
    fi
}

wifi_on() {
    echo "Preparing to toggle wifi on..."

    if ! write_config; then
        return 1
    fi

    if ! service-on; then
        return 1
    fi

    DELAY=30
    for i in $(seq 1 "$DELAY"); do
        STATUS=$(cat "/sys/class/net/wlan0/operstate")
        if [ "$STATUS" = "up" ]; then
            break
        fi
        sleep 1
    done

    if [ "$STATUS" != "up" ]; then
        show_message "Failed to start wifi!" 2
        return 1
    fi
}

network_loop() {
    if ! wifi-enabled; then
        show_message "Enabling wifi..." forever
        if ! service-on; then
            show_message "Failed to enable wifi!" 2
            return 1
        fi
    fi

    next_screen="main"
    while true; do
        SSID="$(networks_screen)"
        exit_code=$?
        # exit codes: 2 = back button (go back to main screen)
        if [ "$exit_code" -eq 2 ]; then
            break
        fi

        # exit codes: 3 = menu button (exit out of the app)
        if [ "$exit_code" -eq 3 ]; then
            next_screen="exit"
            break
        fi

        # some sort of error and then go back to main screen
        if [ "$exit_code" -ne 0 ]; then
            show_message "Error selecting a network" 2
            next_screen="main"
            break
        fi

        password_screen "$SSID"
        exit_code=$?
        # exit codes: 2 = back button (go back to networks screen)
        if [ "$exit_code" -eq 2 ]; then
            continue
        fi

        # exit codes: 3 = menu button (exit out of the app)
        if [ "$exit_code" -eq 3 ]; then
            next_screen="exit"
            break
        fi

        if [ "$exit_code" -ne 0 ]; then
            continue
        fi

        show_message "Connecting to $SSID..." forever
        if ! wifi_on; then
            show_message "Failed to start wifi!" 2
            return 1
        fi

        killall minui-presenter >/dev/null 2>&1 || true
        break
    done

    echo "$next_screen"
}

cleanup() {
    rm -f /tmp/stay_awake
    killall minui-presenter >/dev/null 2>&1 || true
}

main() {
    echo "1" >/tmp/stay_awake
    trap "cleanup" EXIT INT TERM HUP QUIT

    if [ "$PLATFORM" = "tg3040" ] && [ -z "$DEVICE" ]; then
        export DEVICE="brick"
        export PLATFORM="tg5040"
    fi

    allowed_platforms="tg5040 rg35xxplus"
    if ! echo "$allowed_platforms" | grep -q "$PLATFORM"; then
        show_message "$PLATFORM is not a supported platform" 2
        return 1
    fi

    if ! command -v minui-keyboard >/dev/null 2>&1; then
        show_message "minui-keyboard not found" 2
        return 1
    fi

    if ! command -v minui-list >/dev/null 2>&1; then
        show_message "minui-list not found" 2
        return 1
    fi

    if ! command -v minui-presenter >/dev/null 2>&1; then
        show_message "minui-presenter not found" 2
        return 1
    fi

    chmod +x "$PAK_DIR/bin/$architecture/jq"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-keyboard"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-list"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-presenter"

    if [ "$PLATFORM" = "rg35xxplus" ]; then
        RGXX_MODEL="$(strings /mnt/vendor/bin/dmenu.bin | grep ^RG)"
        if [ "$RGXX_MODEL" = "RG28xx" ]; then
            show_message "Wifi not supported on RG28XX" 2
            return 1
        fi
    fi

    while true; do
        selection="$(main_screen)"
        exit_code=$?
        # exit codes: 2 = back button, 3 = menu button
        if [ "$exit_code" -ne 0 ]; then
            break
        fi

        if echo "$selection" | grep -q "^Connect to network$"; then
            next_screen="$(network_loop)"
            if [ "$next_screen" = "exit" ]; then
                break
            fi
        elif echo "$selection" | grep -q "^Enable$"; then
            show_message "Enabling wifi..." forever
            if ! service-on; then
                show_message "Failed to enable wifi!" 2
                continue
            fi
            sleep 2
        elif echo "$selection" | grep -q "^Refresh connection$"; then
            show_message "Disconnecting from wifi..." forever
            if ! wifi_off; then
                show_message "Failed to stop wifi!" 2
                return 1
            fi
            show_message "Refreshing connection..." forever
            if ! service-on; then
                show_message "Failed to enable wifi!" 2
                continue
            fi
            sleep 2
        elif echo "$selection" | grep -q "^Disable$"; then
            show_message "Disconnecting from wifi..." forever
            if ! wifi_off; then
                show_message "Failed to stop wifi!" 2
                return 1
            fi
        elif echo "$selection" | grep -q "^Toggle start on boot$"; then
            if will_start_on_boot; then
                show_message "Disabling start on boot..." forever
                if ! disable_start_on_boot; then
                    show_message "Failed to disable start on boot!" 2
                    continue
                fi
            else
                show_message "Enabling start on boot..." forever
                if ! enable_start_on_boot; then
                    show_message "Failed to enable start on boot!" 2
                    continue
                fi
            fi
        fi
    done
}

main "$@"
