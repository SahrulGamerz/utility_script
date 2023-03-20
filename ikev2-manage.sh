#!/bin/bash

echo "IKEv2 Client Manager	Copyright (c) 2023-2023 YewonKim (Sah)   20 Mar 2023"

VER="0.0.1"
DESC="This script can be used with hwdsl2/ipsec-vpn-server docker images."

CONF_DIR=${CONF_DIR:-/vpn} # If env not set use default
SCRIPT_DIR=/opt/src

Help()
{
   # Display Help
   echo "$DESC"
   echo "Available Command in IKEv2 Client Manager."
   echo
   echo "Syntax: ikev2-manage [-h|v|j|l|a <client_name>|r <client_name>|g <client_name>|c <client_name>]"
   echo "Example: ikev2-manage -a MyClient"
   echo "Example: ikev2-manage -r MyClient"
   echo "Example: ikev2-manage -jg MyClient"
   echo "Example: ikev2-manage -jl"
   echo "Options:"
   echo "a     Add client."
   echo "r     Remove client."
   echo "g     Get client."
   echo "l     Get client list."
   echo "j     Get output in JSON format. Only applied to -g -l"
   echo "c     Check for client existence, create if not exist, return if exist or after create"
   echo "h     Print this Help."
   echo "v     Print software version and exit."
   echo
}

AddClient() 
{
	if [ -d "$CLIENT_DIR" ]; then
		echo "Client $CLIENT_NAME is already existed!"
		exit
	fi
	echo "Client $CLIENT_NAME will be added!"
	bash $SCRIPT_DIR/ikev2.sh --addclient $CLIENT_NAME
	mkdir -p $CLIENT_DIR
	cp /etc/ipsec.d/$CLIENT_NAME.* $CONF_DIR/$CLIENT_NAME
	echo "Client $CLIENT_NAME has been added!"
}

RemoveClient()
{
	if [ ! -d "$CLIENT_DIR" ]; then
		echo "Client $CLIENT_NAME is not existed!"
		exit
	fi
	echo "Client $CLIENT_NAME will be removed!"
	bash $SCRIPT_DIR/ikev2.sh --revokeclient $CLIENT_NAME <<< "y"
	bash $SCRIPT_DIR/ikev2.sh --deleteclient $CLIENT_NAME <<< "y"
	rm -rf $CLIENT_DIR
	echo "Client $CLIENT_NAME has been removed!"
}

GetClient()
{
	if [ ! -d "$CLIENT_DIR" ]; then
		echo "Client $CLIENT_NAME is not existed!"
		exit
	fi
	
	CLIENT_PASSWORD=$(bash $SCRIPT_DIR/ikev2.sh --exportclient $CLIENT_NAME | grep Password -A 1 | sed -n '2p')
	
	if [[ $FORMAT = "JSON" ]]; then
		GetClientJSON
	else
		for f in "$CLIENT_DIR"/*; do	
			echo "$f"
			echo $(base64 $f)
			echo "-----------"
		done
		echo "Client Password: $CLIENT_PASSWORD"
	fi
}

GetClientJSON()
{
	if [ ! -d "$CLIENT_DIR" ]; then
		echo "Client $CLIENT_NAME is not existed!"
		exit
	fi
	
	printf '{ "client_name": "%s", "client_password": "%s", "mobileconfig": "%s", "p12": "%s", "sswan": "%s" }\n' "$CLIENT_NAME" "$CLIENT_PASSWORD" "$(base64 $CLIENT_DIR/$CLIENT_NAME.mobileconfig)" "$(base64 $CLIENT_DIR/$CLIENT_NAME.p12)" "$(base64 $CLIENT_DIR/$CLIENT_NAME.sswan)"
}

# TODO
GetClientList()
{
	bash $SCRIPT_DIR/ikev2.sh --listclients
}
# TODO
GetClientListJSON()
{
	bash $SCRIPT_DIR/ikev2.sh --listclients
}

CheckCreateReturnClient()
{
	if [ ! -d "$CLIENT_DIR" ]; then
		AddClient
	fi
	
	GetClient
}

while getopts ":vhjla:r:g:c:" option; do
   case $option in
      v) # display current version
        echo "IKEv2 Client Manager ver ${VER}"
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
      c) # Check Create Return Client
		CLIENT_NAME=${OPTARG}
		CLIENT_DIR=${CONF_DIR}/${CLIENT_NAME}
		CheckCreateReturnClient
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