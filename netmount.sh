#!/bin/bash

# Simple script that mounts remote folders via sshfs.

# First set some colors for the prompt.
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# We need a config file to load the remote hosts from.
config="/home/dwd/bin/sshfs.lst"
local_dir=/home/dwd/sshfs

# Check if local directory exists. Otherwise create it.
if [ ! -d ~/sshfs ]; then
    
    read -e -p "The folder: $local_dir does not exist. Do you want to create it? [Y/n] " YN
    
    [[ $YN == "y" || $YN == "Y" || $YN == "" ]] && mkdir $local_dir
fi

# Loop through the list and mount if host is available. Otherwise skip and try next in the list.
while read line ;
do
    set $line;
    remote_host="$2@$1:$3"
    local_mount_folder="$4"
    if ping -q -c 1 -W 1 $1 >/dev/null; then
        
        if mountpoint -q $local_mount_folder; then
            echo -e "$remote_host is already mounted to $local_mount_folder - Skipping."
            
        else
            if [ ! -d $local_mount_folder ]; then
                mkdir -p $local_mount_folder;
            fi
            sshfs $remote_host $local_mount_folder -o nonempty
            printf "Mount: $remote_host to: $local_mount_folder - ${GREEN}Ok${NC}\n"
        fi
    else
        printf "$1 appears to be offline. - ${RED}Skipped${NC}\n"
    fi
done < $config