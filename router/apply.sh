#!/bin/sh
# Applied by: make dns-apply
# Clears all existing host records and recreates from stdin (UCI commands)

# Remove all existing host entries
while uci -q delete dhcp.@host[0]; do :; done

# Apply new entries (passed via stdin as UCI commands)
eval "$(cat)"

uci commit dhcp
/etc/init.d/dnsmasq restart
echo "DNS records applied"
