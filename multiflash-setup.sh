#!/usr/bin/env bash

set -euo pipefail
set -x

# The idea is to setup an Network Namespace enviroment to parralize flashing
# in a bunch of VLANs.
# So you get yourself a switch, configure a bunch of untagged VLANs on all
# the ports and then a trunk port for your PC.
# And then you can parralize flashing.
#
# Not finished yet.


if ! command -v nft 2>&1 > /dev/null
then
	echo "nft could not be found but is needed"
	exit 1
fi

if ! command -v ip 2>&1 > /dev/null
then
	echo "ip could not be found but is needed"
	exit 1
fi

if ! command -v jq 2>&1 > /dev/null
then
	echo "jq could not be found but is needed"
	exit 1
fi

# CONFIG Section Start

IFNAME=enp1s0

VID_START=100
VID_INTERVAL=1
VID_STEPS=4

# CONFIG Section End

ip -json link show dev $IFNAME > /dev/null

vid_list=()
for ((i=0; i<VID_STEPS; i++)); do
	vid=$((VID_START + i * VID_INTERVAL))
	vid_list+=("$vid")
done

echo "${vid_list[@]}"

echo "deleting old"
for vid in "${vid_list[@]}" ; do
	echo "handling ${vid}"
	vlanif="${IFNAME}.${vid}"
	nsname="setupns${vid}"

	ip netns delete "${nsname}" 2>&1 > /dev/null || true
	ip link set down "${vlanif}" 2>&1 > /dev/null || true
	ip link delete "${vlanif}"  2>&1 > /dev/null || true
done

echo "creating new"
for vid in "${vid_list[@]}" ; do
	echo "handling ${vid}"
	#vlanif="${IFNAME}.${vid}"
	vlanif="mf-vlan.${vid}"
	nsname="setupns${vid}"

	ip link add link $IFNAME name "${vlanif}" type vlan id $vid || true

	ip netns add "${nsname}"
	ip link set dev "${vlanif}" netns "${nsname}"

	ip netns exec "${nsname}" ip addr add 192.168.1.10/24 dev "${vlanif}"
	ip netns exec "${nsname}" ip link set "${vlanif}" up
	ip netns exec "${nsname}" ip link set lo up
done
