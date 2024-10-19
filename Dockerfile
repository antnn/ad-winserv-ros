#https://www.redhat.com/sysadmin/podman-inside-container
FROM registry.fedoraproject.org/fedora:40 as build

ENV BRIDGE_PUB="public0"\
    PUB_NET="public"\
    BRIDGE_INT="internal0" \
    PROJECT_DIR="/opt/project"\
    DOWNLOADS="/opt/project/downloads"\
    VM_DIR="/opt/vm"\
    TEMPLATE_DIR="/opt/project/templates"\
    WIN_VM_DIR="/opt/vm/win"\
    ROS_VM_DIR="/opt/vm/ros"\
    WIN_VM_NAME="win2k22"\
    ROS_VM_NAME="ros"\
    WIN_XML_FILE="/opt/vm/win/win2k22.domain.xml"\
    ROS_XML_FILE="/opt/vm/ros/ros.xml"\
    NET_NAME="private"\
    ROS_VM_DISK="/opt/vm/ros/drive.img"

ARG ISO_DIR="/iso"
ARG WIN_ISO="win_server.iso"
ARG WIN_IMAGE_INDEX=2
ARG WIN_DRIVE_SIZE="120G"
ARG PWSH_MSI="pwsh.msi"
ARG VIRTIO_ISO="virtio.iso"
ARG ROS_DRIVE="ros.img"
COPY . $PROJECT_DIR

RUN set -Eeuo pipefail; set -o nounset ; set -o errexit ; \
dnf install -y qemu-kvm libvirt virt-manager bridge-utils systemd p7zip-plugins python3 ; \
useradd user -G wheel,libvirt ; \
chmod +x /opt/project/*.sh ; \
source /opt/project/main.sh; build; \
cat "$PROJECT_DIR"/help.txt
#
FROM build
CMD [ "/sbin/init" ]
