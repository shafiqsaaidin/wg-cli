#!/bin/bash

# Local .env
if [ -f .env ]; then
    # Load Environment Variables
    export $(cat /root/wg-cli/.env | grep -v '#' | awk '/=/ {print $1}')
fi

new_client_setup () {
	# Given a list of the assigned internal IPv4 addresses, obtain the lowest still
	# available octet. Important to start looking at 2, because 1 is our gateway.
	octet=2
	while grep AllowedIPs /etc/wireguard/wg0.conf | cut -d "." -f 4 | cut -d "/" -f 1 | grep -q "$octet"; do
		(( octet++ ))
	done
	# Don't break the WireGuard configuration in case the address space is full
	if [[ "$octet" -eq 120 ]]; then
		echo "120 clients are already configured. The WireGuard internal subnet is full!"
		exit
	fi
	key=$(wg genkey)
	psk=$(wg genpsk)
	# Configure client in the server
	cat << EOF >> /etc/wireguard/wg0.conf
# BEGIN_PEER $client
[Peer]
PublicKey = $(wg pubkey <<< $key)
PresharedKey = $psk
AllowedIPs = 10.7.0.$octet/32
# END_PEER $client
EOF
	# Create client configuration
	cat << EOF > /root/wg-cli/config/"$client".conf
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

search_client () {
	echo
	echo "Search for user:"
	read -p "Name: " client
	echo
	sed -n -e "/# BEGIN_PEER $client/ ,/# END_PEER $client/p" /etc/wireguard/wg0.conf
}

delete_client () {
	number_of_clients=$(grep -c '^# BEGIN_PEER' /etc/wireguard/wg0.conf)
	if [[ "$number_of_clients" = 0 ]]; then
		echo
		echo "There are no existing clients!"
		exit
	fi
	echo
	echo "Select the client to remove:"
	grep '^# BEGIN_PEER' /etc/wireguard/wg0.conf | cut -d ' ' -f 3 | nl -s ') '
	read -p "Client: " client_number
	until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
		echo "$client_number: invalid selection."
		read -p "Client: " client_number
	done
	client=$(grep '^# BEGIN_PEER' /etc/wireguard/wg0.conf | cut -d ' ' -f 3 | sed -n "$client_number"p)
	echo
	read -p "Confirm $client removal? [y/N]: " remove
	until [[ "$remove" =~ ^[yYnN]*$ ]]; do
		echo "$remove: invalid selection."
		read -p "Confirm $client removal? [y/N]: " remove
	done
	if [[ "$remove" =~ ^[yY]$ ]]; then
		# The following is the right way to avoid disrupting other active connections:
		# Remove from the live interface
		wg set wg0 peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
		# Remove from the configuration file
		sed -i "/^# BEGIN_PEER $client/,/^# END_PEER $client/d" /etc/wireguard/wg0.conf
		echo
		echo "$client removed!"
	else
		echo
		echo "$client removal aborted!"
	fi
}

sync_a_client() {
	echo
	echo "Resync a client"
	read -p "Name: " client
	
	# Remove user from wireguard interface
	wg set wg0 peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
	
	# Append new client configuration to the WireGuard interface
	wg addconf wg0 <(sed -n "/^# BEGIN_PEER $client/,/^# END_PEER $client/p" /etc/wireguard/wg0.conf)
}

sync_config () {
	echo "Syncing wireguard config..."
	wg syncconf wg0 <(wg-quick strip wg0)
	echo "Done"
	exit
}

block_client () {
	echo
	echo "Enter username to block"
	read -p "Name: " client

	# Search the username and print out to screen
	sed -n -e "/# BEGIN_PEER $client/,+5p" /etc/wireguard/wg0.conf

	echo
	read -p "Block $client ? [y/N]: " block
	until [[ "$block" =~ ^[yYnN]*$ ]]; do
		echo "$block: invalid selection."
		read -p "Block $client ? [y/N]: " block
	done
	if [[ "$block" =~ ^[yY]$ ]]; then
		# Remove from the live interface
		wg set wg0 peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove

		# Add comment to config file
		sed -e "/# BEGIN_PEER $client/,+5 s/^/#/" -i /etc/wireguard/wg0.conf

		echo "$client blocked!"
	else
		echo
		echo "Block $client aborted!"
	fi
}

unblock_client () {
	echo
	echo "Enter username to unblock"
	read -p "Name: " client

	# Search the username and print out to screen
	sed -n -e "/# BEGIN_PEER $client/,+5p" /etc/wireguard/wg0.conf

	echo
	read -p "Unblock $client ? [y/N]: " unblock
	until [[ "$unblock" =~ ^[yYnN]*$ ]]; do
		echo "$unblock: invalid selection."
		read -p "Unblock $client ? [y/N]: " unblock
	done
	if [[ "$unblock" =~ ^[yY]$ ]]; then
		# Uncomment config file
		sed -e "/# BEGIN_PEER $client/,+5 s/^#//" -i /etc/wireguard/wg0.conf

		# Append new client configuration to the WireGuard interface
		wg addconf wg0 <(sed -n "/^# BEGIN_PEER $client/,/^# END_PEER $client/p" /etc/wireguard/wg0.conf)

		echo "$client unblocked!"
	else
		echo
		echo "Unblock $client aborted!"
	fi
}

echo -e "
VPNJE WG-CLI

Select an option:
  1) Add a new user
  2) Search a user
  3) Block a user
  4) Unblock a user
  5) Delete a user
  6) Resync a user
  7) Sync all config
  8) Exit"
read -p "Option: " option
until [[ "$option" =~ ^[1-8]$ ]]; do
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
			while [[ -z "$client" ]] || grep -q "^# BEGIN_PEER $client$" /etc/wireguard/wg0.conf; do
				echo "$client: invalid name."
				read -p "Name: " unsanitized_client
				client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
			done
			echo
			new_client_setup
			# Append new client configuration to the WireGuard interface
			wg addconf wg0 <(sed -n "/^# BEGIN_PEER $client/,/^# END_PEER $client/p" /etc/wireguard/wg0.conf)
			#qrencode < /root/wg-cli/config/"$client.conf" -o /root/wg-cli/config/"$client.png"
			echo -e '\xE2\x86\x91 Sending to telegram group.'
			curl -F document=@"/root/wg-cli/config/$client.conf" https://api.telegram.org/${BOT_TOKEN}/sendDocument?chat_id=${GROUP_ID}
			#curl -F photo=@"/root/wg-cli/config/$client.png" https://api.telegram.org/${BOT_TOKEN}/sendPhoto?chat_id=${GROUP_ID}
			echo
			echo "$client added."
			exit
		;;
		2)
			search_client
			exit
		;;
		3)
			block_client
			exit
		;;
		4)
			unblock_client
			exit
		;;
        5)
			number_of_clients=$(grep -c '^# BEGIN_PEER' /etc/wireguard/wg0.conf)
			if [[ "$number_of_clients" = 0 ]]; then
				echo
				echo "There are no existing clients!"
				exit
			fi
			echo
			echo "Select the user to remove:"
			grep '^# BEGIN_PEER' /etc/wireguard/wg0.conf | cut -d ' ' -f 3 | nl -s ') '
			read -p "Client: " client_number
			until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
				echo "$client_number: invalid selection."
				read -p "Client: " client_number
			done
			client=$(grep '^# BEGIN_PEER' /etc/wireguard/wg0.conf | cut -d ' ' -f 3 | sed -n "$client_number"p)
			echo
			read -p "Confirm $client removal? [y/N]: " remove
			until [[ "$remove" =~ ^[yYnN]*$ ]]; do
				echo "$remove: invalid selection."
				read -p "Confirm $client removal? [y/N]: " remove
			done
			if [[ "$remove" =~ ^[yY]$ ]]; then
				# The following is the right way to avoid disrupting other active connections:
				# Remove from the live interface
				wg set wg0 peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
				# Remove from the configuration file
				sed -i "/^# BEGIN_PEER $client/,/^# END_PEER $client/d" /etc/wireguard/wg0.conf
				echo
				echo "$client removed!"
			else
				echo
				echo "$client removal aborted!"
			fi
			exit
		;;
        6)
			sync_a_client
			exit
        ;;
		7)
			sync_config
			exit
        ;;
		8)
			exit
        ;;
esac