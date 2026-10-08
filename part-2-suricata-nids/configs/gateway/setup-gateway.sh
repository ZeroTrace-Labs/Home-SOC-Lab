#!/usr/bin/env bash
# Turns an Ubuntu VM with two NICs into the lab gateway:
# IP forwarding + NAT for the isolated 172.16.50.0/24 subnet, persisted across reboots.
# Without this, agents behind the gateway show "disconnected" (README, Bottleneck 5 & 8).
#
# Usage: sudo ./setup-gateway.sh [WAN_IFACE] [LAN_SUBNET]
set -euo pipefail

WAN_IFACE="${1:-enp0s1}"
LAN_SUBNET="${2:-172.16.50.0/24}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

echo "[*] Enabling IPv4 forwarding (runtime + persistent)"
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-lab-gateway.conf

echo "[*] Applying NAT + forwarding rules (${LAN_SUBNET} -> ${WAN_IFACE})"
# -C checks for an existing rule so the script is safe to re-run
iptables -t nat -C POSTROUTING -s "$LAN_SUBNET" -o "$WAN_IFACE" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s "$LAN_SUBNET" -o "$WAN_IFACE" -j MASQUERADE
iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -C FORWARD -s "$LAN_SUBNET" -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -s "$LAN_SUBNET" -j ACCEPT

echo "[*] Persisting rules"
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
netfilter-persistent save

echo "[+] Gateway ready."
