#!/bin/bash
set -Eeuo pipefail
set -o nounset
set -o errexit
create_config_iso() {
    local iso_temp_root_build_dir=""
    local drivers_dir="\$WinPeDriver\$"
    local config_iso_output_path=""

    # Parse named arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --build-dir) iso_temp_root_build_dir="$2"; shift ;;
            --output-path) config_iso_output_path="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; return 1 ;;
        esac
        shift
    done

    if [[ -z "$iso_temp_root_build_dir" || -z "$config_iso_output_path" ]]; then
        echo "Error: --build-dir and --output-path are required parameters."
        return 1
    fi

    echo "Creating drivers directory..."
    mkdir -p "$iso_temp_root_build_dir/iso/$drivers_dir"

    echo "Copying entrypoint scripts to iso dir..."
    cp  /opt/project/*.ps1 "$iso_temp_root_build_dir/iso/"
    echo "Copying pwsh scripts to iso dir..."
    cp -r /opt/project/pwsh "$iso_temp_root_build_dir/iso/pwsh"

    mv "$DOWNLOADS/$PWSH_MSI"  "$iso_temp_root_build_dir/iso/pwsh.msi"

    echo "Extracting virtio drivers..."
    7z e "$DOWNLOADS/$VIRTIO_ISO" -o"$iso_temp_root_build_dir/iso/$drivers_dir" \
      -- */2k22/amd64/*

    echo "Creating Windows config ISO..."
    mkisofs -o "$config_iso_output_path" \
        -J -l -R -V "WIN_AUTOINSTALL" \
        -iso-level 4 \
        -joliet-long \
        "$iso_temp_root_build_dir/iso"
    echo "Windows config ISO created successfully at $config_iso_output_path"
}

create_config_iso "$@"