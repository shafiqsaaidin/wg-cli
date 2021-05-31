#!/bin/bash

# Backup Wireguard configuration file.

# Backup file
backup_file="/etc/wireguard/wg0.conf"

# Destination backup file
dest="/root/wg-cli/backup/"

# Check backup directory
if [ -d "$dest" ]; then
    echo "Directory exist"
else
    echo "Creating backup directory"
    mkdir $dest
fi

# Print start status message
echo "Backing up $backup_file to $dest"
date
echo

if [ -f "$backup_file" ]; then
    echo "$backup_file exists."
    cp $backup_file $dest/`date +"%Y-%m-%d"`-wg0.conf
    echo "Backup finished"
    ls -lh $dest
else
    echo "$backup not exist."
fi