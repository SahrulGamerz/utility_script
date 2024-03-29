#!/bin/bash

echo "OpenVPN Client Manager	Copyright (c) 2023-2023 YewonKim (Sah)   20 Mar 2023"

VER="0.0.2"
DESC="This script can be used with nuBacuk/docker-openvpn docker images."

# Check expect is installed
if ! command -v expect &> /dev/null; then
    echo "expect could not be found, installing..."
	if command -v apk &> /dev/null
	then
		apk add --no-cache expect
	else
		echo "failed to install"
		exit
	fi
fi

if [[ $MANAGEMENT_PORT = "" ]]; then
	echo "MANAGEMENT_PORT env is empty or not set"
	exit
fi

Help()
{
   # Display Help
   echo "$DESC"
   echo "Available Command in OpenVPN Client Manager."
   echo
   echo "Syntax: ovpn-manage [-h|v|j|s|o|l|a <client_name>|r <client_name>|g <client_name>|c <client_name>]"
   echo "Example: ovpn-manage -a MyClient"
   echo "Example: ovpn-manage -r MyClient"
   echo "Example: ovpn-manage -jg MyClient"
   echo "Example: ovpn-manage -jl"
   echo "Options:"
   echo "a     Add client."
   echo "r     Remove client."
   echo "g     Get client (in base64)."
   echo "l     Get client list."
   echo "j     Get output in JSON format. Only applied to -g -l"
   echo "s     Get OpenVPN status."
   echo "o     Get OpenVPN load status."
   echo "c	   Check for client existence, create if not exist, return if exist or after create"
   echo "h     Print this Help."
   echo "v     Print software version and exit."
   echo
}

CheckClient()
{
	case `ovpn_getclient $CLIENT_NAME  2>&1 | grep "Unable to find" > /dev/null; echo $?` in
	  0)
		echo "Client $CLIENT_NAME is not existed!"
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
	case `ovpn_getclient $CLIENT_NAME  2>&1 | grep 'Unable to find' > /dev/null; echo $?` in
	  0)
		;;
	  1)
		echo "Client $CLIENT_NAME is existed!"
		exit;;
	  *)
		echo "An error occurred while checking client in conf"
		exit;;
	esac
	/usr/bin/expect <(cat << EOF
spawn easyrsa build-client-full $CLIENT_NAME nopass
expect { 
	-re "Confirm request details:" {send -- "yes\r"}
	-re "Enter pass phrase for /etc/openvpn/pki/private/ca.key:" {send -- "$CERTPASS\r"}
}
expect { 
	-re "Confirm request details:" {send -- "yes\r"}
	-re "Enter pass phrase for /etc/openvpn/pki/private/ca.key:" {send -- "$CERTPASS\r"}
}
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:"
send "$CERTPASS\r"
interact
EOF
)
}

RemoveClient()
{
	CheckClient
	/usr/bin/expect <(cat << EOF
spawn ovpn_revokeclient $CLIENT_NAME remove
expect "Type the word 'yes' to continue, or any other input to abort."
send "yes\r"
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:"
send "$CERTPASS\r"
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:"
send "$CERTPASS\r"
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:"
send "$CERTPASS\r"
interact
EOF
)
}

GetClient()
{
	CheckClient
	ovpn_getclient $CLIENT_NAME > $CLIENT_NAME.ovpn 2> /dev/null;
	if [[ $FORMAT = "JSON" ]]; then
		GetClientJSON
	else
		echo $(base64 $CLIENT_NAME.ovpn)
	fi
	rm $CLIENT_NAME.ovpn
}

GetClientJSON()
{
	CheckClient
	printf '{ "client": "%s" }\n' "$(base64 $CLIENT_NAME.ovpn)"
}
# TODO
GetClientList()
{
	ovpn_listclients
}
# TODO
GetClientListJSON()
{
	ovpn_listclients
}

CheckCreateReturnClient()
{
	if [ ! -d "$CLIENT_DIR" ]; then
		AddClient
	fi
	
	GetClient
}

while getopts ":vhjlosa:r:g:c:" option; do
   case $option in
      v) # display current version
        echo "OpenVPN Client Manager ver ${VER}"
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