#!/bin/sh

DEFAULT_PORTS="80,443,554,5060,8000"

if [ "$#" -eq 0 ]; then
  PORTS="$DEFAULT_PORTS"
else
  PORTS=$(IFS=,; printf '%s' "$*")
fi

NET=$(ip -o -4 addr show | grep "2:" | awk '{print $4}' |
  cut -d/ -f1 | awk -F '.' '{print $1"."$2"."$3".2-255"}')

nmap -n -Pn "$NET" -p "$PORTS" -oG - |
  awk -F '\t' '
    /^Host:/ {
      split($1, host, " ")
      ports = ""
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^Ports: /) {
          sub(/^Ports: /, "", $i)
          count = split($i, entries, ", ")
          for (j = 1; j <= count; j++) {
            split(entries[j], port, "/")
            if (port[2] == "open")
              ports = ports (ports == "" ? "" : ",") port[1]
          }
        }
      }
      if (ports != "")
        printf "%-16s %s\n", host[2], ports
    }
  '