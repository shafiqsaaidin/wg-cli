#!/bin/bash
# use this script to fix older blocked acc

input="name.txt"
wgFile='/etc/wireguard/wg0.conf'

# extract username from wireguard file
grep -w "#PublicKey" -B2 $wgFile | sed -n -e "/^# BEGIN_PEER/p" | awk '{print $3}' > $input

if [ -f "$input" ]; then
    while read p; do
        sed -i "/# BEGIN_PEER $p$/ s/^/#/" $wgFile
        sed -i "/# END_PEER $p$/ s/^/#/" $wgFile
        echo "Normalize done for $p"
    done < $input
else
    echo "$input not exist. Creating $input file... Please rerun the script"
    touch $input
fi