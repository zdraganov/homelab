#!/usr/bin/env python3
"""Generate UCI commands for OpenWrt from router/*.yaml config files"""
import yaml, os

base = os.path.dirname(os.path.abspath(__file__))

# ── DNS host records (DHCP reservations) ──────────────────────────────────────
with open(f"{base}/dns-hosts.yaml") as f:
    data = yaml.safe_load(f)

print("# Clear existing host records")
print("while uci -q delete dhcp.@host[0]; do :; done")
print()

for host in data["hosts"]:
    if not host.get("ip"):
        continue
    print(f"uci add dhcp host")
    print(f"uci set dhcp.@host[-1].name='{host['name']}'")
    print(f"uci set dhcp.@host[-1].ip='{host['ip']}'")
    if "mac" in host:
        print(f"uci set dhcp.@host[-1].mac='{host['mac']}'")
        print(f"uci set dhcp.@host[-1].leasetime='infinite'")

# ── DNS aliases (address records, no DHCP) ────────────────────────────────────
if os.path.exists(f"{base}/dns-aliases.yaml"):
    with open(f"{base}/dns-aliases.yaml") as f:
        adata = yaml.safe_load(f)
    print()
    print("# DNS-only aliases")
    # Clear existing address list entries we manage
    for alias in adata.get("aliases", []):
        print(f"uci -q del_list dhcp.@dnsmasq[0].address='/{alias['name']}.lan/{alias['ip']}'")
        print(f"uci add_list dhcp.@dnsmasq[0].address='/{alias['name']}.lan/{alias['ip']}'")

print()
print("uci commit dhcp")
print("/etc/init.d/dnsmasq restart")

# ── Port forwards ─────────────────────────────────────────────────────────────
with open(f"{base}/port-forwards.yaml") as f:
    pfdata = yaml.safe_load(f)

print()
print("# Clear existing port forwards")
print("while uci -q delete firewall.@redirect[0]; do :; done")
print()

for pf in pfdata["port_forwards"]:
    print(f"uci add firewall redirect")
    print(f"uci set firewall.@redirect[-1].name='{pf['name']}'")
    print(f"uci set firewall.@redirect[-1].target='DNAT'")
    print(f"uci set firewall.@redirect[-1].src='wan'")
    print(f"uci set firewall.@redirect[-1].dest='lan'")
    print(f"uci set firewall.@redirect[-1].proto='{pf.get('proto', 'tcp')}'")
    print(f"uci set firewall.@redirect[-1].src_dport='{pf['src_port']}'")
    print(f"uci set firewall.@redirect[-1].dest_ip='{pf['dest_ip']}'")
    print(f"uci set firewall.@redirect[-1].dest_port='{pf['dest_port']}'")

print()
print("uci commit firewall")
print("/etc/init.d/firewall restart")
