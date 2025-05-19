#!/usr/bin/env bash

set -euo pipefail
set -x

# This scripts that you've statically configured an IP from within 192.168.1.0/24
# on one of your interfaces. You can't choose 192.168.1.1.
# A valid choice could be for example 192.168.1.66/24 (Mask: 255.255.255.0).
#
# You need to supply your own images. A factory image from OpenWrt and a
# sysupgrade Image of your final firmware.
#
# Factory Fimrware: https://downloads.openwrt.org/snapshots/targets/ramips/mt7621/openwrt-ramips-mt7621-genexis_pulse-ex400-factory.bin

FACTORY_FILENAME="openwrt-ramips-mt7621-genexis_pulse-ex400-factory.bin"

SYSUPGRADE_FILENAME="gluon-ffda-3.0.6~20250515-ea0b4f1-genexis-pulse-ex400-sysupgrade.bin"


if [ ! -f "$FACTORY_FILENAME" ]; then
	echo "${FACTORY_FILENAME} doesn't exist. Please add it"
	exit 1
fi

if [ ! -f "$SYSUPGRADE_FILENAME" ]; then
	echo "$SYSUPGRADE_FILENAME doesn't exist. Please add it"
	exit 1
fi

function wait_until_as_expected {
	TARGET_URL=$1
	TARGET_STRING=$2

	echo "Checking wheter \"${TARGET_STRING}\" is present at \"${TARGET_URL}\""
	while true; do
		if curl --connect-timeout 2 -fs "${TARGET_URL}" | grep "${TARGET_STRING}"; then
			echo "found"
			break
		else
			echo "missing. Will try again shortly"
		fi
		sleep 1
	done
}

function uploadFactoryFileEX400 {
	FILENAME=$1

	echo "will now upload factory firmware"

	curl -F "fileID=@${FILENAME}" -F "submit=upload" http://192.168.1.1/firmware_upload -v
}

function repeat_ssh() {
	COMMAND=$1

	until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 root@192.168.1.1 $COMMAND; do
		sleep 2
	done
}

function configure_node() {
	echo "configure contact"
	repeat_ssh "uci get gluon-node-info.@owner[0] || uci add gluon-node-info owner"
	repeat_ssh "uci set gluon-node-info.@owner[0].contact=info@darmstadt.freifunk.net"

	echo "configure ssh"
	repeat_ssh "uci set ffda-ssh-manager.settings.enabled='1'"
	repeat_ssh "uci add_list ffda-ssh-manager.settings.groups='ffda'"

	echo "configuring mesh"
	repeat_ssh "uci del_list gluon.iface_wan.role='uplink'"
	repeat_ssh "uci add_list gluon.iface_wan.role='mesh'"
	repeat_ssh "uci del_list gluon.iface_wan.role='client'"
	repeat_ssh "uci add_list gluon.iface_lan.role='mesh'"

	echo "configure domain"
	repeat_ssh "uci set gluon.core.domain=ffda_da_240"

	echo "disable setup mode"
	repeat_ssh "uci set gluon-setup-mode.@setup_mode[0].enabled='0'"
	repeat_ssh "uci set gluon-setup-mode.@setup_mode[0].configured='1'"

	echo "save all changes"
	repeat_ssh "uci commit"

	echo "configure node according to new parameters"
	repeat_ssh "gluon-reconfigure"

	repeat_ssh "reboot"
}

wait_until_as_expected "http://192.168.1.1/" "fileID"
sleep 2

uploadFactoryFileEX400 "${FACTORY_FILENAME}"
sleep 20

repeat_ssh "uname -a"
sleep 2

echo "copy over gluon"
scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SYSUPGRADE_FILENAME root@192.168.1.1:/tmp/gluon.bin
sleep 1
echo "install gluon"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1 "/sbin/sysupgrade -n /tmp/gluon.bin || true"

#sleep 5
#echo "wait until reachable again"
#repeat_ssh "gluon-info"

#configure
