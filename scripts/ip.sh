#!/bin/bash
#
# Script to setup multi-homed routing on linux
# Jason Ernst
# Redtree Robotics, 2015
#
#
# get the IP address and IF name (returns them as: ifname,ipaddress)
counter=1
for i in $(sudo ifconfig | awk 'BEGIN { FS = "\n"; RS = "" } { print $1 $2 }' | sed -e 's/ .*inet addr:/,/' -e 's/ .*//');
do
	#parse the ip and IF name apart
	IFS=',' read -a vals <<< "$i"
	interface=${vals[0]};
	ipaddr=${vals[1]};

	# only process eth and wlan interfaces for now
	if [[ $interface =~ ^eth ]] || [[ $interface =~ ^wlan ]] || [[ $interface =~ ^usb ]]; then
		if [[ ! -z $ipaddr ]]; then
			counter=$[counter + 1]
			echo "Making table for IF: $interface IP: $ipaddr";

			table="$(cat /etc/iproute2/rt_tables | grep $interface)"
			if [[ $table == "" ]]; then
				echo "Table $interface not found, creating..."
				echo $table
				echo $counter $interface | sudo tee -a /etc/iproute2/rt_tables
			else
				echo "Table $interface found, deleting any entries..."
				sudo ip route flush table $interface
			fi;

			#determine if ubuntu or debian since they both handle dhcp leases differently
			#ubuntu stores in /var/lib/NetworkManager and does dhclient-<uuid>-<ifname>.lease or dhclient6-<uuid>-<ifname>.lease (ipv6)
			#debian in /var/lib/dhcp and does dhclient.<ifname>.leases
			ub=$(cat /etc/os-release | grep 'NAME="Ubuntu"')
			if [[ $ub != "" ]]; then
				echo "Ubuntu";

				# systems that don't use network manager
				if [ ! -e "/var/lib/NetworkManager" ]; then
					lease="$(ls -t /var/lib/dhcp/dhclient.$interface.leases | head -1)"
				else
					lease="$(ls -t /var/lib/NetworkManager/dhclient-*-$interface.lease | head -1)"
				fi
			else
				lease="$(ls -t /var/lib/dhcp/dhclient.$interface.leases | head -1)"
			fi
			router="$(cat $lease | grep 'routers' | tail -n 1 | awk {'sub(/\;$/,"",$3); print $3'})"
			echo "GW: $router"

			mask="$(cat $lease | grep 'subnet-mask' | tail -n 1 | awk {'sub(/\;$/,"",$3); print $3'})"
			echo "MASK: $mask"

			IFS=. read -r i1 i2 i3 i4 <<< $router
			IFS=. read -r m1 m2 m3 m4 <<< $mask
			subnet=$(printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))")
			echo "SUBNET: $subnet"

			# delete all old rules
			IFS=$'\n'
			for r in $(ip rule show | grep $interface | cut -f2-);
			do
				eval sudo ip rule del $r
			done

			sudo ip route add default via $router dev $interface table $interface
			sudo ip route add $subnet/24 dev $interface src $ipaddr table $interface		#todo: determine the /24 number based on subnet / mask

			sudo ip rule add iif $interface lookup $interface
			sudo ip rule add oif $interface lookup $interface

			sudo ip rule add to $ipaddr lookup $interface
			sudo ip rule add from $ipaddr lookup $interface
		fi
	fi
done
