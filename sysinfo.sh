#!/bin/bash

# --- Show help ---
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Use this tool without flags; it will show basic information about your system."
  exit 0
fi

cat <<EOF
#### OS release ####
$(cat /etc/os-release)

#### lsb release ####
$(lsb_release -a 2>&1)

#### Kernel version ####
$(uname -r)
EOF
