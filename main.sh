#!/bin/bash
set -Eeuo pipefail
set -o nounset
set -o errexit
export USER=user


# Converts it to one line to pass to cmd in SynchronousCommand
# Runs from cmd, not from powershell
# Install pwsh 7 to avoid possible powershell 5 bugs in advance
# see https://github.com/antnn/is-it-pwsh-bug-qm/ and https://github.com/microsoft/CSS-Exchange/issues/1917
powershell_script=$(cat <<'EOF' | tr '\n' ';' | sed 's/"/\\"/g'
$defaultEntryPoint = 'start.ps1'
foreach ($drive in [char]'A'..[char]'Z') {
  $defaultFirstLogonCmd = ' '
  $drive = [char]$drive
  $path = "${drive}:\$defaultEntryPoint"
  if (Test-Path ${path}) {
    Start-Process msiexec.exe -ArgumentList "/i ${drive}:\pwsh.msi /passive /qb" -Wait
    Start-Process ${env:ProgramFiles}\PowerShell\7\pwsh.exe -ArgumentList "-NoExit -ExecutionPolicy Bypass -File ${path}"
  }
}
EOF
)
powershell_script="C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -Command \"$powershell_script\""


build() {
  local TEMPLATE_DIR="$PROJECT_DIR/templates"
  local ISO_TEMP_ROOT_BUILD_DIR="/tmp/iso"
  local CONFIG_ISO="$WIN_VM_DIR/config.iso"
  local WIN_SOCKET_MON="/tmp/qemu.win.socket"
  local WIN_MAC_ADDRESS="00:11:22:33:44:55"
  local WIN_IP_ADDRESS="192.168.88.2/24"
  local ROUTER_IP="192.168.88.1"
  mkdir -p "$ISO_TEMP_ROOT_BUILD_DIR/iso"
  mkdir -p "$(dirname "$CONFIG_ISO")"

  echo Generating answerfile
  "$PROJECT_DIR"/generate_autounattend.sh --image-index "$WIN_IMAGE_INDEX" \
    --template-file "$TEMPLATE_DIR/autounattend.template.xml" \
    --output-dir "$ISO_TEMP_ROOT_BUILD_DIR/iso" \
    --lang "ru-RU" --user-name "IEUSER" --user-password "Passw0rd!" \
    --admin-password "Passw0rd!" --computer-name "MAINSERVER" \
    --mac-address "$WIN_MAC_ADDRESS" --ip-address "$WIN_IP_ADDRESS" \
    --route-prefix "0.0.0.0/0" --default-gw "$ROUTER_IP" --dns-server "127.0.0.1" \
    --secondary-dns "1.1.1.1" --setup-command "$powershell_script"


  "$PROJECT_DIR"/create_config_iso.sh --build-dir "$ISO_TEMP_ROOT_BUILD_DIR" \
    --output-path "$CONFIG_ISO"

  local WIN_DRIVE="$WIN_VM_DIR/win.qcow2"
  echo "Creating disk for Windows Server..."
  qemu-img create -f qcow2  "$WIN_DRIVE" "$WIN_DRIVE_SIZE"
  chown $USER "$WIN_DRIVE"

  echo Rendering Windows Server KVM domain template...
  "$PROJECT_DIR"/render_template.sh "$TEMPLATE_DIR"/win2k22.template.xml \
    name="$WIN_VM_NAME" \
    drive="$WIN_DRIVE" \
    mac_address="$WIN_MAC_ADDRESS" \
    bridge="$BRIDGE_INT" \
    os_iso="$ISO_DIR/$WIN_ISO" \
    socket_mon="$WIN_SOCKET_MON" \
    config_iso="$CONFIG_ISO" > "$WIN_XML_FILE"

  mkdir -p  "$ROS_VM_DIR"
  mv "$DOWNLOADS/$ROS_DRIVE" "$ROS_VM_DISK"
  echo "Generating domain xml for RouterOS"
  "$PROJECT_DIR"/render_template.sh "$TEMPLATE_DIR"/routeros.template.xml \
    name="$ROS_VM_NAME"\
    drive="$ROS_VM_DISK"\
    interface1="$BRIDGE_PUB" \
    interface2="$BRIDGE_INT" > "$ROS_XML_FILE"

echo "Defining public network for routeros..."
"$PROJECT_DIR"/render_template.sh "$TEMPLATE_DIR"/public.net.template.xml name="$PUB_NET" bridge="$BRIDGE_PUB" > "$VM_DIR/net.pub.xml"
echo "allow $BRIDGE_PUB" >> /etc/qemu/bridge.conf

echo "Defining internal network for windows server and routeros..."
"$PROJECT_DIR"/render_template.sh "$TEMPLATE_DIR"/internal.net.template.xml name="$NET_NAME" bridge="$BRIDGE_INT" > "$VM_DIR/net.xml"
echo "allow $BRIDGE_INT" >> /etc/qemu/bridge.conf

  generate_units

  systemctl enable virtnetworkd-ro.socket
  systemctl enable startguestnet.service
  systemctl enable setupros.service
  systemctl enable setupguest.service
}

generate_units(){
  UNIT_FILE="/etc/systemd/system/startguestnet.service"
cat << EOF > "$UNIT_FILE"
[Unit]
Description=Network setup for guests
After=network.target virtqemud.service
Requires=virtqemud.service

[Service]
Type=oneshot
ExecStart=/usr/bin/virsh net-define "$VM_DIR/net.pub.xml"
ExecStart=/usr/bin/virsh net-define "$VM_DIR/net.xml"
ExecStart=/bin/bash -c '/usr/bin/virsh net-start $PUB_NET && /usr/bin/virsh net-autostart $PUB_NET'
ExecStart=/bin/bash -c '/usr/bin/virsh net-start $NET_NAME && /usr/bin/virsh net-autostart $NET_NAME'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$UNIT_FILE"

  UNIT_FILE="/etc/systemd/system/setupros.service"
cat << EOF > "$UNIT_FILE"
[Unit]
Description=Guest setup and starting
After=network.target startguestnet.service
Requires=startguestnet.service
[Service]
User=$USER
Type=simple
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/python3 console.py -- --name="$ROS_VM_NAME" &
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$UNIT_FILE"

  UNIT_FILE="/etc/systemd/system/setupguest.service"
cat << EOF > "$UNIT_FILE"
[Unit]
Description=Guest setup and starting
After=network.target startguestnet.service
Requires=startguestnet.service

[Service]
User=$USER
Type=oneshot
WorkingDirectory=/home/$USER
ExecStart=/usr/bin/virsh -c qemu:///session define "$ROS_XML_FILE"
ExecStart=/usr/bin/virsh -c qemu:///session define "$WIN_XML_FILE"
ExecStart=/usr/bin/virsh -c qemu:///session start "$ROS_VM_NAME"
ExecStart=/usr/bin/virsh -c qemu:///session start "$WIN_VM_NAME"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}



# Function to run commands as user
run_as_user() {
    echo Defining RouterOS domain...
    virsh -c qemu:///session define $ROS_XML_FILE
    echo Defining Windows Server KVM domain...
    virsh -c qemu:///session define "$WIN_XML_FILE"

    echo Starting console script
    python3 /opt/project/console.py &
    virsh start "$WIN_VM_NAME"
    virsh start "$ROS_VM_NAME"

    virt-manager -c qemu:///session
}


