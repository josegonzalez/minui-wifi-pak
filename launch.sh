#!/bin/sh
set -x
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"

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
export LD_LIBRARY_PATH="$PAK_DIR/lib/$PLATFORM:$PAK_DIR/lib:$LD_LIBRARY_PATH"
export PATH="$PAK_DIR/bin/$architecture:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"

get_ssid_and_ip() {
    enabled="$(cat /sys/class/net/wlan0/operstate)"
    if [ "$enabled" != "up" ]; then
        return
    fi

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

    printf "%s\t%s" "$ssid" "$ip_address"
}

main_screen() {
    minui_list_file="/tmp/minui-list"
    rm -f "$minui_list_file" "/tmp/minui-output"
    touch "$minui_list_file"

    template_file="$PAK_DIR/res/settings.json"

    start_on_boot=false
    if will_start_on_boot; then
        start_on_boot=true
    fi

    enabled=false
    ssid_and_ip=""
    if wifi-enabled; then
        enabled=true
        template_file="$PAK_DIR/res/settings.enabled.json"
    fi

    ssid_and_ip="$(get_ssid_and_ip)"
    if [ -n "$ssid_and_ip" ]; then
        ssid="$(echo "$ssid_and_ip" | cut -f1)"
        ip_address="$(echo "$ssid_and_ip" | cut -f2)"
        template_file="$PAK_DIR/res/settings.connected.json"
        if [ "$ip_address" = "N/A" ]; then
            template_file="$PAK_DIR/res/settings.no-ip.json"
        fi
    fi

    cp "$template_file" "$minui_list_file"
    if [ "$enabled" = true ]; then
        sed -i "s/IS_ENABLED/1/" "$minui_list_file"
    else
        sed -i "s/IS_ENABLED/0/" "$minui_list_file"
    fi
    if [ "$start_on_boot" = true ]; then
        sed -i "s/IS_START_ON_BOOT/1/" "$minui_list_file"
    else
        sed -i "s/IS_START_ON_BOOT/0/" "$minui_list_file"
    fi
    sed -i "s/NETWORK_SSID/$ssid/" "$minui_list_file"
    sed -i "s/NETWORK_IP_ADDRESS/$ip_address/" "$minui_list_file"

    killall minui-presenter >/dev/null 2>&1 || true
    minui-list --disable-auto-sleep --item-key settings --file "$minui_list_file" --format json --cancel-text "EXIT" --title "Wifi Configuration" --write-location /tmp/minui-output --write-value state
}

networks_screen() {
    minui_list_file="/tmp/minui-list"
    rm -f "$minui_list_file" "/tmp/minui-output"
    touch "$minui_list_file"

    show_message "Scanning for networks" forever
    DELAY=30

    for i in $(seq 1 "$DELAY"); do
        iw dev wlan0 scan | grep SSID: | cut -d':' -f2- | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' | sort >>"$minui_list_file"
        if [ -s "$minui_list_file" ]; then
            break
        fi
        sleep 1
    done

    killall minui-presenter >/dev/null 2>&1 || true
    minui-list --disable-auto-sleep --file "$minui_list_file" --format text --confirm-text "CONNECT" --title "Wifi Networks" --write-location /tmp/minui-output
}

saved_networks_screen() {
    minui_list_file="/tmp/minui-list"
    rm -f "$minui_list_file" "/tmp/minui-output"
    touch "$minui_list_file"

    if [ ! -f "$SDCARD_PATH/wifi.txt" ]; then
        show_message "No wifi.txt file found" 2
        return 1
    fi

    sed '/^#/d; /^$/d; s/:.*//' "$SDCARD_PATH/wifi.txt" >"$minui_list_file"

    if [ ! -s "$minui_list_file" ]; then
        show_message "No saved networks found" 2
        return 1
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    minui-list --disable-auto-sleep --file "$minui_list_file" --format text --title "Wifi Networks" --confirm-text "FORGET" --write-location /tmp/minui-output
}

password_screen() {
    SSID="$1"

    rm -f "/tmp/minui-output"
    touch "$SDCARD_PATH/wifi.txt"

    initial_password=""
    if grep -q "^$SSID:" "$SDCARD_PATH/wifi.txt" 2>/dev/null; then
        initial_password="$(grep "^$SSID:" "$SDCARD_PATH/wifi.txt" | cut -d':' -f2- | xargs)"
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    minui-keyboard --title "Enter Password" --initial-value "$initial_password" --write-location /tmp/minui-output
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

    password="$(cat /tmp/minui-output)"
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
    if [ "$PLATFORM" = "miyoomini" ]; then
        return 0
    fi
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
    ENABLING_WIFI="${1:-true}"

    echo "Generating wpa_supplicant.conf"
    template_file="$PAK_DIR/res/wpa_supplicant.conf.tmpl"
    if [ "$PLATFORM" = "miyoomini" ] || [ "$PLATFORM" = "my282" ]; then
        template_file="$PAK_DIR/res/wpa_supplicant.conf.$PLATFORM.tmpl"
    fi

    cp "$template_file" "$PAK_DIR/res/wpa_supplicant.conf"
    if [ "$PLATFORM" = "rg35xxplus" ]; then
        echo "Generating netplan.yaml"
        cp "$PAK_DIR/res/netplan.yaml.tmpl" "$PAK_DIR/res/netplan.yaml"
    fi

    if [ ! -f "$SDCARD_PATH/wifi.txt" ] && [ -f "$PAK_DIR/wifi.txt" ]; then
        mv "$PAK_DIR/wifi.txt" "$SDCARD_PATH/wifi.txt"
    fi

    touch "$SDCARD_PATH/wifi.txt"
    sed -i '/^$/d' "$SDCARD_PATH/wifi.txt"
    # exit non-zero if no wifi.txt file or empty
    if [ ! -s "$SDCARD_PATH/wifi.txt" ]; then
        echo "No credentials found in wifi.txt"
    fi

    if [ "$ENABLING_WIFI" = "true" ]; then
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
            if [ -z "$ssid" ]; then
                continue
            fi

            has_passwords=true

            {
                echo "network={"
                echo "    ssid=\"$ssid\""
                if [ "$priority_used" = false ]; then
                    echo "    priority=1"
                    priority_used=true
                fi
                if [ -z "$psk" ]; then
                    echo "    key_mgmt=NONE"
                else
                    echo "    psk=\"$psk\""
                fi
                echo "}"
            } >>"$PAK_DIR/res/wpa_supplicant.conf"
            if [ "$PLATFORM" = "rg35xxplus" ]; then
                {
                    echo "                \"$ssid\":"
                    echo "                    password: \"$psk\""
                } >>"$PAK_DIR/res/netplan.yaml"
            fi
        done <"$SDCARD_PATH/wifi.txt"
    fi

    if [ "$PLATFORM" = "miyoomini" ]; then
        cp "$PAK_DIR/res/wpa_supplicant.conf" /etc/wifi/wpa_supplicant.conf
        cp "$PAK_DIR/res/wpa_supplicant.conf" /appconfigs/wpa_supplicant.conf
    elif [ "$PLATFORM" = "my282" ]; then
        cp "$PAK_DIR/res/wpa_supplicant.conf" /etc/wifi/wpa_supplicant.conf
        cp "$PAK_DIR/res/wpa_supplicant.conf" /config/wpa_supplicant.conf
    elif [ "$PLATFORM" = "rg35xxplus" ]; then
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
    echo "Preparing to toggle wifi off"

    if ! write_config "false"; then
        return 1
    fi

    if ! service-off; then
        return 1
    fi
    return 0
}

wifi_on() {
    echo "Preparing to toggle wifi on"

    if ! write_config "true"; then
        return 1
    fi

    if ! service-on; then
        return 1
    fi

    if [ ! -s "$SDCARD_PATH/wifi.txt" ]; then
        show_message "No credentials found in wifi.txt" 2
        return 0
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
        return 1
    fi
}

forget_network_loop() {
    next_screen="main"
    while true; do
        saved_networks_screen
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
            next_screen="main"
            break
        fi

        SSID="$(cat /tmp/minui-output)"
        # remove the SSID from the wifi.txt file
        sed -i "/^$SSID:/d" "$SDCARD_PATH/wifi.txt"
        if ! write_config "true"; then
            show_message "Failed to write wireless config" 2
            break
        fi

        show_message "Refreshing connection" forever

        if ! wifi_off; then
            show_message "Failed to disable wifi" 2
            break
        fi

        if ! wifi_on; then
            show_message "Failed to enable wifi" 2
            break
        fi
        break
    done

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$next_screen" >/tmp/wifi-next-screen
}

network_loop() {
    if ! wifi-enabled; then
        show_message "Enabling wifi" forever
        if ! service-on; then
            show_message "Failed to enable wifi" 2
            return 1
        fi
    fi

    next_screen="main"
    while true; do
        networks_screen
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

        SSID="$(cat /tmp/minui-output)"
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

        show_message "Connecting to $SSID" forever
        if ! wifi_on; then
            show_message "Failed to start wifi" 2
            break
        fi

        break
    done

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$next_screen" >/tmp/wifi-next-screen
}

cleanup() {
    rm -f /tmp/stay_awake /tmp/wifi-next-screen
    killall minui-presenter >/dev/null 2>&1 || true
}

main() {
    echo "1" >/tmp/stay_awake
    trap "cleanup" EXIT INT TERM HUP QUIT

    if [ "$PLATFORM" = "tg3040" ] && [ -z "$DEVICE" ]; then
        export DEVICE="brick"
        export PLATFORM="tg5040"
    fi

    if [ "$PLATFORM" = "miyoomini" ] && [ -z "$DEVICE" ]; then
        export DEVICE="miyoomini"
        if [ -f /customer/app/axp_test ]; then
            export DEVICE="miyoominiplus"
        fi
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

    allowed_platforms="my282 tg5040 rg35xxplus miyoomini"
    if ! echo "$allowed_platforms" | grep -q "$PLATFORM"; then
        show_message "$PLATFORM is not a supported platform" 2
        return 1
    fi

    if [ "$PLATFORM" = "miyoomini" ]; then
        if [ ! -f /customer/app/axp_test ]; then
            show_message "Wifi not supported on non-Plus version of the Miyoo Mini" 2
            return 1
        fi

        if ! grep -c 8188fu /proc/modules; then
            insmod "$PAK_DIR/res/miyoomini/8188fu.ko"
        fi
    fi

    if [ "$PLATFORM" = "rg35xxplus" ]; then
        RGXX_MODEL="$(strings /mnt/vendor/bin/dmenu.bin | grep ^RG)"
        if [ "$RGXX_MODEL" = "RG28xx" ]; then
            show_message "Wifi not supported on RG28XX" 2
            return 1
        fi
    fi

    chmod +x "$PAK_DIR/bin/$architecture/jq"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-keyboard"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-list"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-presenter"

    while true; do
        main_screen
        exit_code=$?
        # exit codes: 2 = back button, 3 = menu button
        if [ "$exit_code" -ne 0 ]; then
            break
        fi

        output="$(cat /tmp/minui-output)"
        selected_index="$(echo "$output" | jq -r '.selected')"
        selection="$(echo "$output" | jq -r ".settings[$selected_index].name")"

        if [ "$selection" = "Enable" ] || [ "$selection" = "Start on boot" ]; then
            selected_option_index="$(echo "$output" | jq -r ".settings[0].selected")"
            selected_option="$(echo "$output" | jq -r ".settings[0].options[$selected_option_index]")"

            if [ "$selected_option" = "true" ]; then
                if ! wifi-enabled; then
                    show_message "Enabling wifi" forever
                    if ! wifi_on; then
                        show_message "Failed to enable wifi" 2
                        continue
                    fi
                fi
            else
                if wifi-enabled; then
                    show_message "Disabling wifi" forever
                    if ! wifi_off; then
                        show_message "Failed to disable wifi" 2
                        continue
                    fi
                fi
            fi

            selected_option_index="$(echo "$output" | jq -r ".settings[1].selected")"
            selected_option="$(echo "$output" | jq -r ".settings[1].options[$selected_option_index]")"

            if [ "$selected_option" = "true" ]; then
                if ! will_start_on_boot; then
                    show_message "Enabling start on boot" forever
                    if ! enable_start_on_boot; then
                        show_message "Failed to enable start on boot" 2
                        continue
                    fi
                fi
            else
                if will_start_on_boot; then
                    show_message "Disabling start on boot" forever
                    if ! disable_start_on_boot; then
                        show_message "Failed to disable start on boot" 2
                        continue
                    fi
                fi
            fi
        elif echo "$selection" | grep -q "^Connect to network$"; then
            network_loop
            next_screen="$(cat /tmp/wifi-next-screen)"
            if [ "$next_screen" = "exit" ]; then
                break
            fi
        elif echo "$selection" | grep -q "^Forget a network$"; then
            forget_network_loop
            next_screen="$(cat /tmp/wifi-next-screen)"
            if [ "$next_screen" = "exit" ]; then
                break
            fi
        elif echo "$selection" | grep -q "^Refresh connection$"; then
            show_message "Disconnecting from wifi" forever
            if ! wifi_off; then
                show_message "Failed to stop wifi" 2
                return 1
            fi

            show_message "Updating wifi config" forever
            if ! write_config "true"; then
                show_message "Failed to write config" 2
            fi

            show_message "Refreshing connection" forever
            if ! service-on; then
                show_message "Failed to enable wifi" 2
                continue
            fi
        fi
    done
}

main "$@"
