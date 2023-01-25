#!/bin/bash

VER="0.0.1"
DESC="This script can be used in all linux version. This will output network utilization in JSON format."

if [ -d "/sys/class/net/enp0s3" ]; then
        dev=enp0s3
elif [ -d "/sys/class/net/ens3" ]; then
        dev=ens3
elif [ -d "/sys/class/net/eth0" ]; then
        dev=eth0
else
        dev=false
fi

if [ "${dev}" == "false" ]; then
        printf '{"rx_bytes_sec":0, "tx_bytes_sec":0, "rx_bytes":0, "tx_bytes":0, "timestamp":0}\n'
else
        rx=$(cat /sys/class/net/$dev/statistics/rx_bytes)
        tx=$(cat /sys/class/net/$dev/statistics/tx_bytes)

        sleep 1

        newrx=$(cat /sys/class/net/$dev/statistics/rx_bytes)
        newtx=$(cat /sys/class/net/$dev/statistics/tx_bytes)

        difrx=$((newrx-rx))
        diftx=$((newtx-tx))

        timestamp=$(date +%s%N | cut -b1-13)

        printf '{"rx_bytes_sec":%d, "tx_bytes_sec":%d, "rx_bytes":%d, "tx_bytes":%d, "timestamp":%d}\n' "$difrx" "$diftx" "$newrx" "$newtx" "$timestamp"
fi