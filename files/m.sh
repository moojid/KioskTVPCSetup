#!/bin/bash
# Debian terminal network diagnostics

export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

SCRIPT_PATH=$(readlink -f "$0")
INTERFACE=$(ip -4 route show default | awk '/default/ { print $5; exit }')

if [[ -z "$INTERFACE" ]]; then
    INTERFACE=$(ip -o link show up | awk -F ': ' '$2 != "lo" { sub(/@.*/, "", $2); print $2; exit }')
fi

DEFAULT_TARGET="${1:---localnet}"

if (( EUID != 0 )); then
    exec sudo "$SCRIPT_PATH" "$@"
fi

pause() {
    echo
    read -r -p "Press Enter to return to the menu..." _
}

run() {
    echo
    "$@" 2>&1
    local status=$?

    if (( status != 0 )); then
        echo
        echo "Command finished with status $status."
    fi
}

scan_hosts() {
    local mode="$1"
    local target raw status ip report ports
    local count=0
    local -a ips=()

    if ! command -v arp-scan >/dev/null; then
        echo "arp-scan is not installed."
        return
    fi

    if [[ "$mode" == "ports" ]] && ! command -v nmap >/dev/null; then
        echo "nmap is not installed."
        return
    fi

    echo
    echo "ARP discovery only reaches devices on the attached local network."
    read -r -p "IPv4 subnet (Enter for $DEFAULT_TARGET): " target || return
    target="${target:-$DEFAULT_TARGET}"

    if [[ "$target" != "--localnet" &&
          ! "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        echo "Use an IPv4 address, CIDR subnet, or --localnet."
        echo "Example: 192.168.1.0/24"
        return
    fi

    echo
    echo "Discovering hosts on $INTERFACE..."
    raw=$(arp-scan \
        --ouifile=/usr/share/arp-scan/ieee-oui.txt \
        --macfile=/etc/arp-scan/mac-vendor.txt \
        --ignoredups \
        --interface="$INTERFACE" \
        "$target" 2>&1)
    status=$?

    # Show the original results, including MAC addresses and vendors.
    printf '%s\n' "$raw"

    if (( status != 0 )); then
        echo
        echo "ARP discovery failed (status $status)."
        return
    fi

    if [[ "$mode" == "arp" ]]; then
        return
    fi

    # Extract unique IPv4 addresses from successful ARP replies.
    mapfile -t ips < <(
        printf '%s\n' "$raw" |
        awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]/ {
            if (!seen[$1]++) print $1
        }'
    )

    if (( ${#ips[@]} == 0 )); then
        echo
        echo "No hosts replied to ARP discovery."
        return
    fi
    echo
    echo "Scanning ${#ips[@]} hosts together: 100 common TCP ports."
    echo "Please wait; the results table appears when scanning finishes."
    echo

    # One Nmap process scans the discovered hosts in parallel.
    # Leave stderr visible so warnings/errors aren't hidden.
    report=$(nmap -n -Pn -sS -F -T4 \
        --host-timeout 30s \
        -e "$INTERFACE" \
        -oG - \
        "${ips[@]}")
    status=$?

    if (( status != 0 )); then
        echo "Nmap failed (status $status)."
        printf '%s\n' "$report"
        return
    fi

    printf '%-18s | %s\n' "IP address" "Open TCP ports"
    printf '%s\n' "----------------------------------------------------------------"

    printf '%s\n' "$report" |
        awk -F '\t' -v targets="${ips[*]}" '
        /^Host: / {
            split($1, host, " ")
            ip = host[2]

            for (i = 2; i <= NF; i++) {
                if ($i ~ /^Ports: /) {
                    completed[ip] = 1
                    field = $i
                    sub(/^Ports: /, "", field)
                    n = split(field, entries, ",")

                    for (j = 1; j <= n; j++) {
                        entry = entries[j]
                        sub(/^[[:space:]]+/, "", entry)
                        split(entry, port, "/")

                        if (port[2] == "open") {
                            ports[ip] = ports[ip] \
                                (ports[ip] ? ", " : "") \
                                port[1] "/" port[3]
                        }
                    }
                }
                if ($i ~ /^Ignored State: /) {
                    completed[ip] = 1
                }
            }
        }
        END {
            n = split(targets, hosts, " ")
            for (i = 1; i <= n; i++) {
                ip = hosts[i]

                if (ports[ip] != "")
                    result = ports[ip]
                else if (completed[ip])
                    result = "None found among ports tested"
                else
                    result = "No completed port result; possibly timed out"

                printf "%-18s | %s\n", ip, result
            }
        }'

    printf '%s\n' "----------------------------------------------------------------"

}

discover_switch() {
    echo
    echo "Listening for one LLDP advertisement, up to 65 seconds."
    echo "The switch must have LLDP enabled on this port."
    echo

    timeout --foreground 65 \
        tcpdump -nn -e -vvv -s 1500 \
        -i "$INTERFACE" -c 1 \
        'ether proto 0x88cc' 2>&1

    local status=$?

    if (( status == 124 )); then
        echo
        echo "No LLDP advertisement received before timeout."
    elif (( status != 0 )); then
        echo
        echo "Capture ended with status $status."
    fi
}

list_mdns_hosts() {
    if ! command -v avahi-browse >/dev/null; then
        echo "avahi-utils is not installed."
        return
    fi

    echo
    printf '%-15s %-30s %s\n' "IP address" "Hostname" "Service name"
    printf '%s\n' "----------------------------------------------------------------"
    avahi-browse -artp | awk -F ';' '$1 == "=" && $3 == "IPv4" && !seen[$8]++ {
        printf "%-15s %-30s %s\n", $8, $7, $4
    }'
}

while true; do
    clear
    printf 'Debian Network Diagnostics\n'
    printf 'Interface: %s\n\n' "$INTERFACE"

    printf '%s\n' \
        "  1) Interface status and IP addresses" \
        "  2) Ethernet link details" \
        "  3) Discover switch (listen for LLDP)" \
        "  4) Discover hosts and scan common TCP ports" \
        "  5) Discover hosts (ARP only)" \
        "  6) Show routes" \
        "  7) Ping a host" \
        "  8) View cached LLDP/CDP neighbors" \
        "  9) Change interface" \
        " 10) List mDNS/Bonjour hostnames" \
        "  0) Exit"

    echo
    read -r -p "Choose an option: " choice || break

    case "$choice" in
        1)
            run ip -details link show dev "$INTERFACE"
            run ip address show dev "$INTERFACE"
            ;;
        2)
            run ethtool "$INTERFACE"
            ;;
        3)
            discover_switch
            ;;
        4)
            scan_hosts ports
            ;;
        5)
            scan_hosts arp
            ;;
        6)
            echo
            echo "IPv4 routes:"
            run ip -4 route show
            echo
            echo "IPv6 routes:"
            run ip -6 route show
            ;;
        7)
            echo
            read -r -p "Hostname or IP address: " host

            if [[ "$host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.:%_-]*$ ]]; then
                run ping -I "$INTERFACE" -c 4 -W 2 "$host"
            else
                echo "Enter a hostname or IP address without spaces."
            fi
            ;;
        8)
            echo
            echo "Cached neighbors require lldpd to already be running."
            echo "CDP results also depend on its protocol configuration."
            echo "An empty list does not prove that no switch is connected."
            run lldpcli show neighbors details
            ;;
        9)
            echo
            ip -brief link show
            echo
            read -r -p "Interface name: " selected

            if [[ "$selected" =~ ^[a-zA-Z0-9_.:-]+$ &&
                  -e "/sys/class/net/$selected" ]]; then
                INTERFACE="$selected"
                continue
            else
                echo "Interface not found."
            fi
            ;;
        10)
            list_mdns_hosts
            ;;
        0|q|Q)
            break
            ;;
        *)
            echo "Choose one of the listed options."
            ;;
    esac

    pause
done
