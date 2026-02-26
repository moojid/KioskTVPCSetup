DEFAULT_PORT=80

if [ -z "$1" ]; then
  PORT="$DEFAULT_PORT"
else
  PORT="$1"
fi

NET=$(ip -o -4 addr show | grep "2:"|awk '{print $4}' | cut -d/ -f1 | awk -F '.' '{print $1"."$2"."$3".2-255"}')

nmap -n -Pn $NET -p$PORT -oG - | grep '/open/' | awk '/Host:/{print $2}'