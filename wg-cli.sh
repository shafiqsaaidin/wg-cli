#!/bin/bash

# Variables
WG_INT="wg0"
BOT_API=
GROUP_ID=

new_client_setup () {
	# Given a list of the assigned internal IPv4 addresses, obtain the lowest still
	# available octet. Important to start looking at 2, because 1 is our gateway.
	octet=2
	while grep AllowedIPs /etc/wireguard/${WG_INT}.conf | cut -d "." -f 4 | cut -d "/" -f 1 | grep -q "$octet"; do
		(( octet++ ))
	done
	# Don't break the WireGuard configuration in case the address space is full
	if [[ "$octet" -eq 255 ]]; then
		echo "253 clients are already configured. The WireGuard internal subnet is full!"
		exit
	fi
	key=$(wg genkey)
	psk=$(wg genpsk)
	# Configure client in the server
	cat << EOF >> /etc/wireguard/${WG_INT}.conf
# BEGIN_PEER $client
[Peer]
PublicKey = $(wg pubkey <<< $key)
PresharedKey = $psk
AllowedIPs = 10.7.0.$octet/32
# END_PEER $client
EOF
	# Create client configuration
	cat << EOF > ~/"$client".conf
[Interface]
Address = 10.7.0.$octet/24
DNS = 8.8.8.8, 8.8.4.4
PrivateKey = $key

[Peer]
PublicKey = $(grep PrivateKey /etc/wireguard/wg0.conf | cut -d " " -f 3 | wg pubkey)
PresharedKey = $psk
AllowedIPs = 0.0.0.0/0
Endpoint = $(grep '^# ENDPOINT' /etc/wireguard/wg0.conf | cut -d " " -f 3):$(grep ListenPort /etc/wireguard/wg0.conf | cut -d " " -f 3)
PersistentKeepalive = 25
EOF
}

check_client () {
	sed -n -e '/# BEGIN_PEER tgiskandar/ ,/# END_PEER tgiskandar/p' /etc/wireguard/wg0.conf
}

delete_client () {
	number_of_clients=$(grep -c '^# BEGIN_PEER' /etc/wireguard/${WG_INT}.conf)
	if [[ "$number_of_clients" = 0 ]]; then
		echo
		echo "There are no existing clients!"
		exit
	fi
	echo
	echo "Select the client to remove:"
	grep '^# BEGIN_PEER' /etc/wireguard/${WG_INT}.conf | cut -d ' ' -f 3 | nl -s ') '
	read -p "Client: " client_number
	until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
		echo "$client_number: invalid selection."
		read -p "Client: " client_number
	done
	client=$(grep '^# BEGIN_PEER' /etc/wireguard/${WG_INT}.conf | cut -d ' ' -f 3 | sed -n "$client_number"p)
	echo
	read -p "Confirm $client removal? [y/N]: " remove
	until [[ "$remove" =~ ^[yYnN]*$ ]]; do
		echo "$remove: invalid selection."
		read -p "Confirm $client removal? [y/N]: " remove
	done
	if [[ "$remove" =~ ^[yY]$ ]]; then
		# The following is the right way to avoid disrupting other active connections:
		# Remove from the live interface
		wg set ${WG_INT} peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/${WG_INT}.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
		# Remove from the configuration file
		sed -i "/^# BEGIN_PEER $client/,/^# END_PEER $client/d" /etc/wireguard/${WG_INT}.conf
		echo
		echo "$client removed!"
	else
		echo
		echo "$client removal aborted!"
	fi
}

sync_config () {
	echo "Reloading wireguard config..."
	wg syncconf ${WG_INT} <(wg-quick strip ${WG_INT})
	echo "Done"
	exit
}

echo -e "
VPNJE WG-CLI

Select an option:
  1) Add a new user
  2) Disable an existing user
  3) Delete an existing user
  4) Sync wireguard config"
read -p "Option: " option
until [[ "$option" =~ ^[1-4]$ ]]; do
        echo "$option: invalid selection."
        read -p "Option: " option
done
case "$option" in
		1)
			echo
			echo "Provide a name for the user:"
			read -p "Name: " unsanitized_client
			# Allow a limited set of characters to avoid conflicts
			client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
			while [[ -z "$client" ]] || grep -q "^# BEGIN_PEER $client$" /etc/wireguard/${WG_INT}.conf; do
				echo "$client: invalid name."
				read -p "Name: " unsanitized_client
				client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
			done
			echo
			new_client_setup
			# Append new client configuration to the WireGuard interface
			wg addconf ${WG_INT} <(sed -n "/^# BEGIN_PEER $client/,/^# END_PEER $client/p" /etc/wireguard/${WG_INT}.conf)
			echo
			qrencode -t UTF8 < ~/"$client.conf"
			echo -e '\xE2\x86\x91 That is a QR code containing your client configuration.'
			echo
			echo "$client added. Configuration available in:" ~/"$client.conf"
			exit
		;;
        3)
			# This option could be documented a bit better and maybe even be simplified
			# ...but what can I say, I want some sleep too
			number_of_clients=$(grep -c '^# BEGIN_PEER' /etc/wireguard/${WG_INT}.conf)
			if [[ "$number_of_clients" = 0 ]]; then
				echo
				echo "There are no existing clients!"
				exit
			fi
			echo
			echo "Select the user to remove:"
			grep '^# BEGIN_PEER' /etc/wireguard/${WG_INT}.conf | cut -d ' ' -f 3 | nl -s ') '
			read -p "Client: " client_number
			until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
				echo "$client_number: invalid selection."
				read -p "Client: " client_number
			done
			client=$(grep '^# BEGIN_PEER' /etc/wireguard/${WG_INT}.conf | cut -d ' ' -f 3 | sed -n "$client_number"p)
			echo
			read -p "Confirm $client removal? [y/N]: " remove
			until [[ "$remove" =~ ^[yYnN]*$ ]]; do
				echo "$remove: invalid selection."
				read -p "Confirm $client removal? [y/N]: " remove
			done
			if [[ "$remove" =~ ^[yY]$ ]]; then
				# The following is the right way to avoid disrupting other active connections:
				# Remove from the live interface
				wg set ${WG_INT} peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/${WG_INT}.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
				# Remove from the configuration file
				sed -i "/^# BEGIN_PEER $client/,/^# END_PEER $client/d" /etc/wireguard/${WG_INT}.conf
				echo
				echo "$client removed!"
			else
				echo
				echo "$client removal aborted!"
			fi
			exit
		;;
        4)

        ;;
esac