#!/bin/bash
set -Eeuo pipefail
set -o nounset
set -o errexit
if [ $# -lt 1 ]; then
    echo "Usage: $0 <input_file> [key1=value1] [key2=value2] ..."
    exit 1
fi

input_file="$1"
shift

if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' not found."
    exit 1
fi

temp_file=$(mktemp)

cp "$input_file" "$temp_file"

for arg in "$@"; do
    key="${arg%%=*}"
    value="${arg#*=}"

    escaped_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')

    sed -i "s|{{$key}}|$escaped_value|g" "$temp_file"
done


cat "$temp_file"
rm "$temp_file"