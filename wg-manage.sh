#!/bin/bash

VER="0.0.1"
DESC="This script can be used with linuxserver/wireguard images."
IPS_USED=${IPS_USED:-./config/ips.txt} # If env not set use default
CONF_DIR=${CONF_DIR:-./config/clients} # If env not set use default
SERVER_CONF_DIR=${SERVER_CONF_DIR:-./config/server} # If env not set use default
WG_CONF=${WG_CONF:-./config/wg0.conf} # If env not set use default
INTERFACE=$(echo "$INTERNAL_SUBNET" | awk 'BEGIN{FS=OFS="."} NF--')

if [[ $INTERFACE = "" ]]; then
	echo "Failed to fetch interface ip, might be due to INTERNAL_SUBNET Env is empty"
	exit
fi

if [[ $SERVERURL = "" ]]; then
	echo "SERVERURL Env is empty, please set SERVERURL"
	exit
fi

if [[ $SERVERPORT = "" ]]; then
	echo "SERVERPORT Env is empty, please set SERVERPORT"
	exit
fi

if [[ ! -f "$IPS_USED" ]]; then
    echo "Creating ips.txt"
	echo "" > $IPS_USED
fi

# Remove empty line
sed -i.bak -r '/^\s*$/d' $IPS_USED

Help()
{
   # Display Help
   echo "$DESC"
   echo "Available Command in WireGuard Client Manager."
   echo
   echo "Syntax: wg-manage [-h|v|j|l|a <client_name>|r <client_name>|g <client_name>]"
   echo "Example: wg-manage -a MyClient"
   echo "Example: wg-manage -r MyClient"
   echo "Example: wg-manage -jg MyClient"
   echo "Example: wg-manage -jl"
   echo "Options:"
   echo "a     Add client."
   echo "r     Remove client."
   echo "g     Get client."
   echo "l     Get client list."
   echo "j     Get output in JSON format. Only applied to -g -l"
   echo "h     Print this Help."
   echo "v     Print software version and exit."
   echo
}

RemoveFromConf()
{
	if [ -f "$CLIENT_DIR/publickey-${CLIENT_NAME}" ]; then
		PUB_KEY=$(cat $CLIENT_DIR/publickey-${CLIENT_NAME})
	else
		PUB_KEY=$(sed -n "/# $CLIENT_NAME START/,/# $CLIENT_NAME END/p" $WG_CONF | awk '/PublicKey/ {print $3}')
	fi

	# Get client ip
	CLIENT_IP=$(sed -n "/$CLIENT_NAME /p" $IPS_USED | awk '{print $2}')
	
	# Create backup and Remove from conf
	sed -i.bak "/# ${CLIENT_NAME} START/,/# ${CLIENT_NAME} END/d" $WG_CONF
	sed -i.bak -r '/^\s*$/d' $WG_CONF
	
	# Create backup and Remove used ips conf
	sed -i.bak "/${CLIENT_NAME} /d" $IPS_USED
	sed -i.bak -r '/^\s*$/d' $IPS_USED
	
	# Remove routes
	echo "wg set wg0 peer ${PUB_KEY} remove"
	echo "ip -4 route delete ${INTERFACE}.${CLIENT_IP}/32 dev wg0"
	wg set wg0 peer $PUB_KEY remove
	ip -4 route delete ${INTERFACE}.${CLIENT_IP}/32 dev wg0
}

CheckClient() 
{
	
	if [ -d "$CLIENT_DIR" ]; then
		echo "Client $CLIENT_NAME is already existed!"
		exit
	fi
	
	# First pass
	case `grep -Fx "# ${CLIENT_NAME} START" "$WG_CONF" > /dev/null; echo $?` in
	  0)
		echo "First Pass: Client $CLIENT_NAME existed in $WG_CONF. Deleting..."
		RemoveFromConf;;
	  1)
		;;
	  *)
		echo "An error occurred while checking client in conf"
		exit;;
	esac
	
	
	# Second pass
	case `grep -Fx "# ${CLIENT_NAME} START" "$WG_CONF" > /dev/null; echo $?` in
	  0)
		echo "Second Pass: Client $CLIENT_NAME existed in $WG_CONF. Deleting..."
		RemoveFromConf
		exit;;
	  1)
		;;
	  *)
		echo "An error occurred while checking client in conf"
		exit;;
	esac
}

AddClient()
{
	CheckClient
	# Create Pub and Priv key
	mkdir -p $SERVER_CONF_DIR
    if [ ! -f $SERVER_CONF_DIR/privatekey-server ]; then
		umask 077
		wg genkey | tee  $SERVER_CONF_DIR/privatekey-server | wg pubkey >  $SERVER_CONF_DIR/publickey-server
	fi
	
	echo "Client $CLIENT_NAME will be added!"
	# Generate random clients ip
	while : ; do
		CLIENT_IP=$(( $RANDOM % 254 + 2 ))
		case `grep -Fx "$CLIENT_NAME $CLIENT_IP" "$IPS_USED" > /dev/null; echo $?` in
		  0)
			echo "IP is beind used: ${CLIENT_IP}"
			;;
		  1)
			echo "$CLIENT_NAME $CLIENT_IP" >> $IPS_USED
			echo "Using IP: ${INTERFACE}.${CLIENT_IP}"
			break;;
		  *)
			echo "An error occurred while checking existing ip with random ip"
			exit;;
		esac
	done

	# Add to clients folder
	mkdir -p $CLIENT_DIR
	umask 077
	wg genkey | tee $CLIENT_DIR/privatekey-${CLIENT_NAME} | wg pubkey > $CLIENT_DIR/publickey-${CLIENT_NAME}
	wg genpsk > $CLIENT_DIR/presharedkey-${CLIENT_NAME}

	echo "[Interface]" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "Address = ${INTERFACE}.${CLIENT_IP}/32" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "PrivateKey = $(cat $CLIENT_DIR/privatekey-${CLIENT_NAME})" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "ListenPort = 51820" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "DNS = ${PEERDNS:-1.1.1.1, 1.0.0.1}" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "" >> $CLIENT_DIR/${CLIENT_NAME}.conf 
	echo "[Peer]" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "PublicKey = $(cat $SERVER_CONF_DIR/publickey-server)" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "PresharedKey = $(cat $CLIENT_DIR/presharedkey-${CLIENT_NAME})" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "Endpoint = ${SERVERURL}:${SERVERPORT}" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	echo "AllowedIPs = ${ALLOWEDIPS:-0.0.0.0/0, ::/0}" >> $CLIENT_DIR/${CLIENT_NAME}.conf
	
	# Add to wg0.conf
	echo "" >> $WG_CONF
	echo "# ${CLIENT_NAME} START" >> $WG_CONF
	echo "[Peer]" >> $WG_CONF
	echo "PublicKey = $(cat $CLIENT_DIR/publickey-${CLIENT_NAME})" >> $WG_CONF
	echo "PresharedKey = $(cat $CLIENT_DIR/presharedkey-${CLIENT_NAME})" >> $WG_CONF
	echo "AllowedIPs = ${INTERFACE}.${CLIENT_IP}/32" >> $WG_CONF
	echo "# ${CLIENT_NAME} END" >> $WG_CONF
	
	# Add routes
	echo "wg set wg0 peer $(cat $CLIENT_DIR/publickey-${CLIENT_NAME}) preshared-key $CLIENT_DIR/presharedkey-${CLIENT_NAME} allowed-ips ${INTERFACE}.${CLIENT_IP}/32"
	echo "ip -4 route add ${INTERFACE}.${CLIENT_IP}/32 dev wg0"
	wg set wg0 peer $(cat $CLIENT_DIR/publickey-${CLIENT_NAME}) preshared-key $CLIENT_DIR/presharedkey-${CLIENT_NAME} allowed-ips ${INTERFACE}.${CLIENT_IP}/32
	ip -4 route add ${INTERFACE}.${CLIENT_IP}/32 dev wg0
	echo "Client $CLIENT_NAME has been added!"
}

RemoveClient()
{
	if [ ! -d "$CLIENT_DIR" ]; then
		case `grep -Fx "# ${CLIENT_NAME} START" "$WG_CONF" > /dev/null; echo $?` in
		  1)
			echo "Client $CLIENT_NAME is not existed!"
			exit;;
		  0)
			;;
		  *)
			echo "An error occurred while checking client in conf"
			exit;;
		esac
	fi
	
	echo "Client $CLIENT_NAME will be removed!"
	RemoveFromConf
	rm -rf $CLIENT_DIR
	echo "Client $CLIENT_NAME has been removed!"
}

GetClient()
{
	if [ ! -d "$CLIENT_DIR" ]; then
		echo "Client $CLIENT_NAME is not existed!"
		exit
	fi
	
	if [[ $FORMAT = "JSON" ]]; then
		GetClientJSON
	else
		cat $CLIENT_DIR/${CLIENT_NAME}.conf
	fi
}

GetClientJSON()
{
	if [ ! -d "$CLIENT_DIR" ]; then
		echo "Client $CLIENT_NAME is not existed!"
		exit
	fi
	
	CLIENT_CFG=$CLIENT_DIR/${CLIENT_NAME}.conf
	address=$(cat $CLIENT_CFG | awk -F"=" '/Address/ {print $2}' | awk '{$1=$1};1')
	priv_key=$(cat $CLIENT_CFG | awk '/PrivateKey/ {print $3}' | awk '{$1=$1};1')
	listen_port=$(cat $CLIENT_CFG | awk '/ListenPort/ {print $3}' | awk '{$1=$1};1')
	dns=$(cat $CLIENT_CFG | awk -F"=" '/DNS/ {print $2}' | awk '{$1=$1};1')
	pub_key=$(cat $CLIENT_CFG | awk '/PublicKey/ {print $3}' | awk '{$1=$1};1')
	psk_key=$(cat $CLIENT_CFG | awk '/PresharedKey/ {print $3}' | awk '{$1=$1};1')
	endpoint=$(cat $CLIENT_CFG | awk '/Endpoint/ {print $3}' | awk '{$1=$1};1')
	allowed_ips=$(cat $CLIENT_CFG | awk -F"=" '/AllowedIPs/ {print $2}' | awk '{$1=$1};1')
	timestamp=$(date +%s%N | cut -b1-13)
	
	printf '{ "wireguard": { "client_name": "%s", "interface": { "address": "%s", "private_key": "%s", "listen_port": "%s", "dns": "%s" }, "peer": { "public_key": "%s", "psk_key": "%s", "endpoint": "%s", "allowed_ips": "%s" } }, "timestamp": %d }\n' "$CLIENT_NAME" "$address" "$priv_key" "$listen_port" "$dns" "$pub_key" "$psk_key" "$endpoint" "$allowed_ips" "$timestamp"
}

GetClientList()
{
	if [[ $FORMAT = "JSON" ]]; then
		GetClientListJSON
	else
		printf 'Client\tIP Address\n'
		for d in $CONF_DIR/* ; do
			CLIENT_NAME=$(echo $d | awk -F"$CONF_DIR/" '{print $2}')
			if [[ $CLIENT_NAME = "*" ]]; then
				break
			fi
			CLIENT_DIR=${CONF_DIR}/${CLIENT_NAME}
			CLIENT_CFG=$CLIENT_DIR/${CLIENT_NAME}.conf
			address=$(cat $CLIENT_CFG | awk -F"=" '/Address/ {print $2}' | awk '{$1=$1};1')
			printf '%s\t%s\n' "$CLIENT_NAME" "$address"
		done
	fi
}

GetClientListJSON()
{
	clientArr=()
	for d in $CONF_DIR/* ; do
		CLIENT_NAME=$(echo $d | awk -F"$CONF_DIR/" '{print $2}')
		if [[ $CLIENT_NAME = "*" ]]; then
			break
		fi
		CLIENT_DIR=${CONF_DIR}/${CLIENT_NAME}
		CLIENT_CFG=$CLIENT_DIR/${CLIENT_NAME}.conf
		address=$(cat $CLIENT_CFG | awk -F"=" '/Address/ {print $2}' | awk '{$1=$1};1')
		clientArr+=("{ \"client\": \"$CLIENT_NAME\", \"address\": \"$address\" }") # Will left with a trailing comma
	done
	joined=$(printf '%s, ' "${clientArr[@]}" | sed 's/.$//g' | sed 's/.$//g')
	printf '{ "clients": [ %s ] }\n' "${joined}"
}

while getopts ":vhjla:r:g:" option; do
   case $option in
      v) # display current version
        echo "WireGuard Client Manager ver ${VER}"
        exit;;
      h) # display Help
        Help
        exit;;
      j) # JSON format
		FORMAT=JSON;;
      a) # Add Client
		CLIENT_NAME=${OPTARG}
		CLIENT_DIR=${CONF_DIR}/${CLIENT_NAME}
		AddClient
		exit;;
      r) # Remove Client
		CLIENT_NAME=${OPTARG}
		CLIENT_DIR=${CONF_DIR}/${CLIENT_NAME}
		RemoveClient
		exit;;
      g) # Get Client
		CLIENT_NAME=${OPTARG}
		CLIENT_DIR=${CONF_DIR}/${CLIENT_NAME}
		GetClient
		exit;;
      l) # Get Client List
		GetClientList
		exit;;
     \?) # Invalid option
        echo "Error: Invalid option"
        exit;;
   esac
done

Help