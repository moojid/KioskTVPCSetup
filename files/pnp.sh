IFACE=$(ip -o link show | grep -oP '^\d+: \Kenp[^:]+' | head -n1)
IP=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
pnp=$(upnpc  -a $IP 22 2222 TCP 3595)
curl -X POST -F data="$pnp" -F store="$CPID" -F ip="$IP" $PING_URL| json_pp