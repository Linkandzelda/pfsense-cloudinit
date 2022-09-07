#!/usr/bin/env bash

NETWORK_CONFIG_PATH=""
USER_DATA_PATH=""

function get_networks() {
	cat $1 | grep "type: physical" -A 7
}

function get_network_item_by_name() {
	get_networks $1 | grep "name: $2" -A 6
}

function get_network_names() {
	get_networks $1 | grep "name: " | grep -v "mac_address" | awk '{print $2}'
}

function get_network_key_value() {
	get_network_item_by_name $1 $2 | grep -v "mac_address" | grep $3 | awk '{print $2}' | tr -d "'"
}

function get_network_interface_name() {
	echo $1 | sed 's/eth/vtnet/g'
}

function get_user_data_hostname() {
	cat $1 | grep "hostname:" | awk '{print $2}'
}

if [ "$1" == "apply" ]; then
	# mount cd roms
	for cd in /dev/cd*; do
		CD_NAME=$(basename $cd)
		mkdir /media/$CD_NAME
		mount_cd9660 /dev/$CD_NAME /media/$CD_NAME

		if [ -f "/media/$CD_NAME/network-config" ]; then
			NETWORK_CONFIG_PATH="/media/$CD_NAME/network-config"
			USER_DATA_PATH="/media/$CD_NAME/user-data"

			continue
		fi
	done

	if [ -z "$NETWORK_CONFIG_PATH" ]; then
		echo "no cd with cloudinit data found, exiting"
		exit 1
	fi
	if [ -z "$USER_DATA_PATH" ]; then
		echo "no cd with cloudinit data found, exiting"
		exit 1
	fi

	HOSTNAME="$(get_user_data_hostname $USER_DATA_PATH)"

	interface_assign_string=""
	for network in $(get_network_names $NETWORK_CONFIG_PATH); do
		INTERFACE="$(get_network_interface_name $network)"
		interface_assign_string="${interface_assign_string}${INTERFACE}\n"
	done

	echo "Interface assign string: $interface_assign_string"

	{ echo "n"; printf "$interface_assign_string"; echo "y"; } | /etc/rc.initial.setports

	netcount=1
	for network in $(get_network_names $NETWORK_CONFIG_PATH); do
		INTERFACE="$(get_network_interface_name $network)"
		IP="$(get_network_key_value $NETWORK_CONFIG_PATH $network 'address')"
		NETMASK="$(get_network_key_value $NETWORK_CONFIG_PATH $network 'netmask')"
		GATEWAY="$(get_network_key_value $NETWORK_CONFIG_PATH $network 'gateway')"

		# if the gatwway is set the same as the IP, set the gateway to nothing
		if [ "$GATEWAY" == "$IP" ]; then
			GATEWAY=""
		fi

		echo "configuring network: $INTERFACE"
		echo IP: $IP
		echo NETMASK: $NETMASK
		echo GATEWAY: $GATEWAY

		ifconfig $INTERFACE $IP/24

		if [ ! -z "$GATEWAY" ]; then
			if [ "$INTERFACE" == "vtnet0" ]; then
				route add default $GATEWAY
			elif [ ! -z "$GATEWAY" ]; then
				route add -net $IP/24 default $GATEWAY
			fi
		fi

		ping -c 1 8.8.8.8

		if [ "$INTERFACE" == "vtnet0" ]; then
			{ echo "$netcount"; echo "n"; echo "$IP/24"; echo "$GATEWAY"; echo "n"; echo ""; echo ""; } | /etc/rc.initial.setlanip	
		else
			{ echo "$netcount"; echo "$IP/24"; echo "$GATEWAY"; echo ""; echo "n"; echo ""; } | /etc/rc.initial.setlanip	
		fi

		echo "Configured interface: $INTERFACE"

		netcount=$((netcount + 1))
		sleep 2
	done

	echo "setting hostname: $HOSTNAME"

	IP="$(get_network_key_value $NETWORK_CONFIG_PATH eth0 'address')"
	
	if ! grep "$IP $HOSTNAME" /etc/hosts
	then
		echo "adding /etc/hosts entry: $IP $HOSTNAME"
		echo "$IP $HOSTNAME" >> /etc/hosts
	fi
fi

