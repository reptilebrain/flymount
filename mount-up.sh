#!/bin/bash

# flymount - A simple script to mount remote folders via sshfs.
# Copyright (C) 2026  P-A Jonasson
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# Colors for output

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Configuration
config="$HOME/bin/targets.conf"
base_mount_dir="$HOME/mnt"

# Ensure the base mount directory exists
if [ ! -d "$base_mount_dir" ]; then
    read -r -e -p "Base directory $base_mount_dir missing. Create it? [Y/n] " YN
    if [[ "$YN" =~ ^[Yy]$ || "$YN" == "" ]]; then
        mkdir -p "$base_mount_dir"
    fi
fi

# Check if the config file exists
if [ ! -f "$config" ]; then
    echo "Error: Config file missing at $config"
    echo "Expected CSV format: host,user,remote_path,local_path"
    exit 1
fi

# Process the targets
# We use a block to handle the header and the loop
{
    # Read and discard the header line
    read -r _

    # Read the rest using comma as separator
    while IFS=',' read -r host user remote_path local_path || [[ -n "$host" ]];
    do
        # Skip empty lines or comments (lines starting with #)
        if [[ -z "$host" || "$host" == \#* ]]; then
            continue
        fi

        # Remove potential carriage returns if file was edited in Windows
        local_path=$(echo "$local_path" | tr -d '\r')

        remote_target="$user@$host:$remote_path"
        
        # Check connectivity
        if ping -q -c 1 -W 1 "$host" >/dev/null; then
            
            # Check if already mounted
            if mountpoint -q "$local_path"; then
                echo -e "$remote_target is already mounted - Skipping."
            else
                # Ensure local mount point exists
                if [ ! -d "$local_path" ]; then
                    mkdir -p "$local_path"
                fi
                
                # Execute mount
                if sshfs "$remote_target" "$local_path" -o nonempty; then
                    printf "Mount: %s to %s - ${GREEN}Ok${NC}\n" "$remote_target" "$local_path"
                else
                    printf "Mount: %s - ${RED}Failed${NC}\n" "$remote_target"
                fi
            fi
        else
            printf "%s is offline - ${RED}Skipped${NC}\n" "$host"
        fi
    done 
} < "$config"