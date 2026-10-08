#!/bin/bash
# Wazuh Active Response: block/unblock an attacker IP with iptables-legacy.
#
# Install on the AGENT (e.g. taron-ubuntu-srv):
#   sudo cp custom-drop.sh /var/ossec/active-response/bin/custom-drop.sh
#   sudo chown root:wazuh /var/ossec/active-response/bin/custom-drop.sh
#   sudo chmod 750 /var/ossec/active-response/bin/custom-drop.sh
#
# Why a custom script? In this lab the stock `firewall-drop` kept logging
# "Invalid input format" and never wrote a rule, and Ubuntu's default `iptables`
# is the nftables backend. This script parses the JSON that wazuh-execd sends,
# validates the IP, and calls iptables-legacy directly. See Part 1 README, Bottleneck 10.

LOGFILE="/var/ossec/logs/active-responses.log"
log() { echo "$(date '+%Y/%m/%d %H:%M:%S') custom-drop: $*" >> "$LOGFILE"; }

# wazuh-execd sends one JSON message per line on stdin.
read -r INPUT

# Prints "<command> <srcip>" or nothing. JSON only, no regex guessing.
PARSED=$(printf '%s' "$INPUT" | python3 -c '
import sys, json, ipaddress
try:
    msg = json.loads(sys.stdin.read())
    cmd = msg["command"]
    ip = msg["parameters"]["alert"]["data"]["srcip"]
    ipaddress.IPv4Address(ip)          # reject anything that is not a valid IPv4
    print(cmd, ip)
except Exception as e:
    print("ERROR", e, file=sys.stderr)
' 2>>"$LOGFILE")

read -r CMD SRCIP <<< "$PARSED"

if [ -z "$SRCIP" ]; then
    log "no valid srcip in message, nothing to do"
    exit 0
fi

case "$CMD" in
    add)
        iptables-legacy -C INPUT -s "$SRCIP" -j DROP 2>/dev/null \
            || iptables-legacy -I INPUT 1 -s "$SRCIP" -j DROP
        log "blocked $SRCIP"
        ;;
    delete)
        iptables-legacy -D INPUT -s "$SRCIP" -j DROP 2>/dev/null
        log "unblocked $SRCIP"
        ;;
    *)
        log "ignoring command '$CMD'"
        ;;
esac
exit 0
