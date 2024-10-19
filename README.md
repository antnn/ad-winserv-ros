Для работы нужно скачать iso Windows Server eval 2022 `ARG WIN_ISO="win_server.iso"` в iso директорию  <br>
Я разработал Docker-контейнер для тестирования сценария, в котором Mikrotik выступает в роли маршрутизатора для Windows Server с установкой роли Active Directory. <br>
Для упрощения воспроизведения среды я использую Dockerfile и скрипты.
<br>
Основная логика реализована в главном скрипте (main)
Маршрутизатор имеет два таких интерфейса: один для внутренней сети, другой для внешней.
<br>
Первоначальная настройка маршрутизатора выполняется автоматически с помощью Python-скрипта console, который взаимодействует с консольным портом виртуальной машины, аналогично утилите expect.<br>
Все команды для настройки маршрутизатора хранятся в файле router.sh.
<br>
Установка Windows Server также происходит автоматически, включая настройку сети (статический IP-адрес).<br>
Для этого генерируется конфигурационный ISO-образ, содержащий файл ответов и необходимые драйверы.
<br>
Результат работы можно наблюдать через графический интерфейс virt-manager. <br>
Однако, просмотр GUI недоступен до завершения работы скрипта настройки маршрутизатора, так как доступ к консоли является эксклюзивным.
<br>


Need to download iso Windows Server eval 2022 `ARG WIN_ISO="win_server.iso"` to iso dir <br>
I've developed a Docker container to test a scenario where Mikrotik serves as a router for a Windows Server running Active Directory. <br>
To streamline the reproduction process, I've utilized Dockerfiles and scripts, with the core logic residing in the main script.
The setup involves creating virtual bridge interfaces for the virtual machines.<br>
The router is configured with two such interfaces - one for the internal network and another for the external network.<br>
The router's initial configuration is fully automated from scratch. This is achieved using a Python script named 'console', which interacts with the virtual machine's console port, similar to the 'expect' utility.<br> 
All router commands are sourced from the router.sh file.<br>
The Windows Server installation process is also automated, including static network configuration. <br>
A configuration ISO image is generated, containing answer files and necessary drivers.<br>
To visualize the results, you can use the virt-manager GUI. However, it's important to note that accessing the GUI is not possible until the router configuration script completes its execution, as console access is exclusive during this process.


download deps


```bash
set -Eeuo pipefail
set -o nounset
set -o errexit

export VIRTIO_ISO="virtio.iso"
export PWSH_MSI="pwsh.msi"
export ROS_DRIVE="ros.img"

download_dir="downloads"
mkdir -p "$download_dir"
( cd "$download_dir"

#DOWNLOAD_CMD="curl -L"
DOWNLOAD_CMD="aria2c -x16 -s16"
download_and_verify() {
    local url="$1"
    local filename="$2"
    local checksum="$3"
    
    if [[ -f "$filename" ]] && echo "$checksum $filename" | sha256sum -c --quiet; then
        echo "Checksum verified for existing $filename"
    else
        echo "Downloading $filename..."
          $DOWNLOAD_CMD "$url" -o "$filename"
          echo "$checksum $filename" | sha256sum -c || { echo "Checksum verification failed for $filename"; exit 1; }

        echo "Download and verification of $filename complete"
    fi
}
# Download and verify VIRTIO_ISO
virtio_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.262-2/virtio-win-0.1.262.iso"
virtio_iso_checksum="bdc2ad1727a08b6d8a59d40e112d930f53a2b354bdef85903abaad896214f0a3"
download_and_verify "$virtio_url" "$VIRTIO_ISO" "$virtio_iso_checksum"

# Download and verify PWSH_MSI
pwsh_url="https://github.com/PowerShell/PowerShell/releases/download/v7.4.5/PowerShell-7.4.5-win-x64.msi"
pwsh_sha="4d0286cc70c2e45404ad940ef96394b191da45d7de46340b05c013eef41c1eec"
download_and_verify "$pwsh_url" "$PWSH_MSI" "$pwsh_sha"

#add Mikrotik Cloud Hosted Router raw img
ros_url=""
ros_sha=""
download_and_verify "$ros_url" "${ROS_DRIVE}1" "$ros_sha"
funzip "${ROS_DRIVE}1" > "$ROS_DRIVE"
)
```
start with 
```bash
IMAGE_NAME="image_name"
NAME='name'
podman build --build-arg ROS_DRIVE="$ROS_DRIVE" --build-arg PWSH_MSI="$PWSH_MSI"\
    --build-arg VIRTIO_ISO="$VIRTIO_ISO" -t "$IMAGE_NAME" .

USERID=$(id -u); 
podman run --rm -it --privileged\
  --security-opt label=disable\
  --cap-add=sys_admin,net_admin,net_raw,mknod,sys_ptrace\
  --device=/dev/fuse\
  --device=/dev/urandom\
  --device=/dev/kvm\
  --device=/dev/dri\
  --device=/dev/net/tun\
  -e XDG_RUNTIME_DIR=/run/user/$USERID\
  -e WAYLAND_DISPLAY=wayland-0\
  -v /run/user/$USERID/wayland-0:/tmp/wayland-0:z\
  -v $PWD/iso:/iso\
  --name "$NAME" "$IMAGE_NAME"
```
in different terminal
```bash
podman exec -it "$NAME" bash
sudo -u user bash
virt-manager -c qemu:///session
```
to test vpn
```bash
#podman exec -it "$NAME" bash
bash $PROJECT_DIR/sstp_vpn.sh
```s
