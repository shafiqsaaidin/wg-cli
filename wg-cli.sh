#!/bin/bash

# Color code
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BOLD=$(tput bold;)
RESET=$(tput sgr0)

# Local .env
if [ -f .env ]; then
    # Load Environment Variables
    export $(cat /root/wg-cli/.env | grep -v '#' | awk '/=/ {print $1}')
fi

get_total_user () {
	CMD=$(grep -w "BEGIN_PEER" /etc/wireguard/wg0.conf | wc -l)
	echo "${GREEN}${BOLD}${CMD}${RESET}"
	exit
}

get_total_blocked_user () {
	CMD2=$(grep -w "#PublicKey" /etc/wireguard/wg0.conf | wc -l)
	echo "${RED}${BOLD}${CMD2}${RESET}"
	exit
}

new_client_setup () {
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

	# Append new client configuration to the WireGuard interface
	wg addconf wg0 <(sed -n "/^# BEGIN_PEER $client/,/^# END_PEER $client/p" /etc/wireguard/wg0.conf)
	#qrencode < /root/wg-cli/config/"$client.conf" -o /root/wg-cli/config/"$client.png"
	echo -e '\xE2\x86\x91 Sending to telegram group.'
	curl -F document=@"/root/wg-cli/config/$client.conf" https://api.telegram.org/${BOT_TOKEN}/sendDocument?chat_id=${GROUP_ID}
	#curl -F photo=@"/root/wg-cli/config/$client.png" https://api.telegram.org/${BOT_TOKEN}/sendPhoto?chat_id=${GROUP_ID}
	echo
	echo "$client added."
	main_menu
}

search_client () {
	echo
	echo "Search for user:"
	read -p "Name: " client
	echo
	sed -n -e "/# BEGIN_PEER $client/ ,/# END_PEER $client/p" /etc/wireguard/wg0.conf
	main_menu
}

delete_client () {
    # get username from argument
    user_name=$1

    disabled=$(grep -x "## BEGIN_PEER $user_name" /etc/wireguard/wg0.conf | wc -l)

	number_of_clients=$(grep -c '^# BEGIN_PEER' /etc/wireguard/wg0.conf)
	if [[ "$number_of_clients" = 0 ]]; then
		echo
		echo "There are no existing clients!"
		exit
	fi
	echo

    # check if the acc is disable before remove
    if [ $disabled -eq 1 ]; then
        # Remove from the live interface
        wg set wg0 peer "$(sed -n "/^## BEGIN_PEER $user_name$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
        sed -i "/^## BEGIN_PEER $user_name$/,/^## END_PEER $user_name$/d" /etc/wireguard/wg0.conf
    else
        wg set wg0 peer "$(sed -n "/^# BEGIN_PEER $user_name$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
        sed -i "/^# BEGIN_PEER $user_name$/,/^# END_PEER $user_name$/d" /etc/wireguard/wg0.conf
    fi
    
    echo
    echo "${RED}${BOLD}$user_name removed!${RESET}"
}

sync_a_client() {
	echo
	echo "Resync a client"
	read -p "Name: " client
	
	# Remove user from wireguard interface
	wg set wg0 peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
	
	# Append new client configuration to the WireGuard interface
	wg addconf wg0 <(sed -n "/^# BEGIN_PEER $client$/,/^# END_PEER $client$/p" /etc/wireguard/wg0.conf)
	main_menu
}

sync_config () {
	echo "Syncing wireguard config..."
	wg syncconf wg0 <(wg-quick strip wg0)
	echo "Done"
	main_menu
}

block_client () {
    # get client username from argument $1
    client=$1

	echo
    # Remove from the live interface
    wg set wg0 peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove

    # Add comment to config file
    sed -e "/# BEGIN_PEER $client$/,+5 s/^/#/" -i /etc/wireguard/wg0.conf

    # Resync wireguard config
    wg syncconf wg0 <(wg-quick strip wg0)

    echo -e "${RED}${BOLD}$client blocked!${RESET}"
}

unblock_client () {
	echo
	echo "Enter username to unblock"
	read -p "Name: " client

	# Search the username and print out to screen
	sed -n -e "/# BEGIN_PEER $client$/,+5p" /etc/wireguard/wg0.conf

	echo
	read -p "Unblock $client ? [y/N]: " unblock
	until [[ "$unblock" =~ ^[yYnN]*$ ]]; do
		echo "$unblock: invalid selection."
		read -p "Unblock $client ? [y/N]: " unblock
	done
	if [[ "$unblock" =~ ^[yY]$ ]]; then
		# Uncomment config file
		sed -e "/# BEGIN_PEER $client$/,+5 s/^#//" -i /etc/wireguard/wg0.conf

		# Append new client configuration to the WireGuard interface
		wg addconf wg0 <(sed -n "/^# BEGIN_PEER $client$/,/^# END_PEER $client$/p" /etc/wireguard/wg0.conf)

		# Resync wireguard config
		wg syncconf wg0 <(wg-quick strip wg0)

		echo
		# Ouput the result of unblocking to screen
		sed -n -e "/# BEGIN_PEER $client$/,+5p" /etc/wireguard/wg0.conf

		echo
		echo -e "$client ${GREEN}${BOLD}unblocked!${RESET}"
	else
		echo
		echo "Unblock $client aborted!"
	fi
	main_menu
}

batch_block () {
    # input file
    input="name.txt"

    if [ -f "$input" ]; then
        while read p; do
            block_client $p
        done < $input
    else
        echo "$input not exist. Creating $input file... Please rerun the script"
        touch $input
    fi
}

batch_delete () {
    # input file
    input="name.txt"

    if [ -f "$input" ]; then
        while IFS= read -r line
        do
            delete_client $line
        done < "$input"
    else
        echo "$input not exist. Creating $input file... Please rerun the script"
        touch $input
    fi
}

main_menu () {
	echo -e "
${GREEN}${BOLD}VPNJE WG-CLI USER MANAGEMENT${RESET}

TOTAL USER: $(get_total_user)
TOTAL DISABLED: $(get_total_blocked_user)

======================
Select an option:
  ${YELLOW}1)${RESET} Add a new user
  ${YELLOW}2)${RESET} Search a user
  ${YELLOW}3)${RESET} Block a user
  ${YELLOW}4)${RESET} Unblock a user
  ${YELLOW}5)${RESET} Delete a user
  ${YELLOW}6)${RESET} Resync a user
  ${YELLOW}7)${RESET} Batch Block user
  ${YELLOW}8)${RESET} Batch Delete user
  ${YELLOW}9)${RESET} Sync all config
  ${YELLOW}0)${RESET} Exit
======================	
"
	read -p "Option [${YELLOW}0 - 9${RESET}]: " option
	until [[ "$option" =~ ^[0-9]$ ]]; do
		echo "$option: invalid selection."
		read -p "Option: " option
	done
	case "$option" in
		1)
			new_client_setup
		;;
		2)
			search_client
		;;
		3)
            echo
	        echo "Enter username to block"
	        read -p "Name: " client
            echo
            # Search the username and print out to screen
	        sed -n -e "/# BEGIN_PEER $client$/,+5p" /etc/wireguard/wg0.conf
            echo
            read -p "Confirm $client block? [y/N]: " block
            until [[ "$block" =~ ^[yYnN]*$ ]]; do
                echo "$block: invalid selection."
                read -p "Confirm $client block? [y/N]: " block
            done
            if [[ "$block" =~ ^[yY]$ ]]; then
                block_client $client
            else
                echo
                echo "$client block aborted!"
            fi
            main_menu
		;;
		4)
			unblock_client
		;;
		5)
            echo
	        echo "Enter username to delete"
	        read -p "Name: " client
            echo
            # Search the username and print out to screen
	        sed -n -e "/# BEGIN_PEER $client$/,+5p" /etc/wireguard/wg0.conf
            echo
            read -p "Confirm $client removal? [y/N]: " remove
            until [[ "$remove" =~ ^[yYnN]*$ ]]; do
                echo "$remove: invalid selection."
                read -p "Confirm $client removal? [y/N]: " remove
            done
            if [[ "$remove" =~ ^[yY]$ ]]; then
                delete_client $client
            else
                echo
                echo "$client removal aborted!"
            fi
            main_menu
		;;
		6)
			sync_a_client
		;;
        7)
			batch_block
            main_menu
		;;
        8)
            batch_delete
            main_menu
		;;
		9)
			sync_config
		;;
		0)
			exit
		;;
	esac
}

main_menu