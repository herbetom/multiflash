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


IFNAME=enp0s20f0u2
#IFNAME=enp0s20f0u1
IFNAME=enp0s20f0u2u1

VID_START=100
VID_INTERVAL=1
VID_STEPS=4


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
	ip link delete "veth${vid}" 2>&1 > /dev/null || true
done

#exit

for vid in "${vid_list[@]}" ; do
	echo "handling ${vid}"
	#vlanif="${IFNAME}.${vid}"
	vlanif="mf-vlan.${vid}"
	nsname="setupns${vid}"

	ip link add link $IFNAME name "${vlanif}" type vlan id $vid || true
	ip link add "veth${vid}" type veth peer name "veth${vid}-ns"

	ip netns add "${nsname}"
	ip link set dev "${vlanif}" netns "${nsname}"
	ip link set dev "veth${vid}-ns" netns "${nsname}"

	ip netns exec "${nsname}" ip addr add 192.168.1.10/24 dev "${vlanif}"
	ip netns exec "${nsname}" ip link set "${vlanif}" up
	ip netns exec "${nsname}" ip link set lo up

	#ip netns exec "${nsname}" ip addr add 192.168.1.10/24 dev "veth${vid}-ns"
	ip netns exec "${nsname}" ip addr add fe80::a/64 dev "veth${vid}-ns"

	ip netns exec "${nsname}" ip link set "veth${vid}-ns" up

	#ip addr add fe80::a/64 dev "veth${vid}"
	ip link set "veth${vid}" up

	ip route add 10.168.$vid.0/24 via inet6 fe80::a dev "veth${vid}"


	ip netns exec "${nsname}" nft add table nat
	ip netns exec "${nsname}" nft 'add chain nat postrouting { type nat hook postrouting priority 100 ; }'
	ip netns exec "${nsname}" nft 'add chain nat prerouting { type nat hook prerouting priority -100 ; }'

	ip netns exec "${nsname}" nft add rule nat postrouting counter
	ip netns exec "${nsname}" nft add rule nat prerouting counter
	#ip netns exec "${nsname}" nft add rule nat postrouting ip daddr 10.168.$vid.0/24 counter snat ip prefix to ip saddr map { 10.168.$vid.0/24 : 192.168.1.0/24 }
	#ip netns exec "${nsname}" nft add rule nat prerouting ip daddr 10.168.$vid.0/24 counter dnat ip prefix to ip saddr map { 10.168.$vid.0/24 : 192.168.1.0/24 }


	#ip netns exec "${nsname}" nft add rule nat prerouting ip daddr 10.168.$vid.0/24 counter ip daddr map { type ipv4_addr : ipv4_addr elements = { 10.168.$vid.0/24 : 192.168.1.0/24 } } dnat to ip daddr map
	ip netns exec "${nsname}" nft add rule nat prerouting ip daddr 10.168.$vid.1 counter dnat to 192.168.1.1

	ip netns exec "${nsname}" nft add rule nat postrouting oifname "${vlanif}" counter masquerade

done



#ip link add link eth0 name eth0.100 type vlan id 100
