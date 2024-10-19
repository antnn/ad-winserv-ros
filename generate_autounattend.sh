#!/bin/bash
set -Eeuo pipefail
set -o nounset
set -o errexit
generate_autounattend() {
    local template_path=""
    local output_dir=""
    local image_index=""
    local lang=""
    local user_name=""
    local user_password=""
    local admin_password=""
    local computer_name=""
    local mac_address=""
    local ip_address=""
    local route_prefix=""
    local default_gw=""
    local dns_server=""
    local secondary_dns=""
    local setup_command=""

    # Parse named arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --image-index) image_index="$2"; shift ;;
            --lang) lang="$2"; shift ;;
            --user-name) user_name="$2"; shift ;;
            --user-password) user_password="$2"; shift ;;
            --admin-password) admin_password="$2"; shift ;;
            --computer-name) computer_name="$2"; shift ;;
            --mac-address) mac_address="$2"; shift ;;
            --ip-address) ip_address="$2"; shift ;;
            --route-prefix) route_prefix="$2"; shift ;;
            --default-gw) default_gw="$2"; shift ;;
            --dns-server) dns_server="$2"; shift ;;
            --secondary-dns) secondary_dns="$2"; shift ;;
            --setup-command) setup_command="$2"; shift ;;
            --template-file) template_path="$2"; shift ;;
            --output-dir) output_dir="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
    done

    # Convert MAC address format 00:11 -> 00-11
    mac_address="${mac_address//:/-}"

    /opt/project/render_template.sh "$template_path" \
        image_index="$image_index" \
        lang="$lang" \
        user_name="$user_name" \
        user_password="$user_password" \
        admin_password="$admin_password" \
        computer_name="$computer_name" \
        mac_address="$mac_address" \
        ip_address="$ip_address" \
        route_prefix="$route_prefix" \
        default_gw="$default_gw" \
        dns_server="$dns_server" \
        secondary_dns="$secondary_dns" \
        setup_command="$setup_command" > "$output_dir/autounattend.xml"

    echo "Generated autounattend.xml in $output_dir"
}

generate_autounattend "$@"