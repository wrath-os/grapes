#!/bin/sh
set -u
deadline=$(( $(date +%s) + $1 ))
checks=$2

unit_ok() {
    state=$(systemctl show -P ActiveState "$1")
    result=$(systemctl show -P Result "$1")
    [ "$state" = active ] || { [ "$state" = inactive ] && [ "$result" = success ] &&
        [ "$(systemctl show -P ExecMainStartTimestampMonotonic "$1")" != 0 ]; }
}

check() {
    case $1 in
        unit) unit_ok "$2" ;;
        ping) ping -c 1 -W 2 "$2" >/dev/null 2>&1 ;;
        resolve) getent ahosts "$2" >/dev/null 2>&1 ;;
        tcp) curl -s --connect-timeout 3 "telnet://$2" </dev/null >/dev/null 2>&1 ;;
        http) curl -sf --max-time 5 -o /dev/null "$2" ;;
    esac
}

failed=""
for item in $(jq -r '.[] | "\(.kind)=\(.target)"' "$checks"); do
    kind=${item%%=*}
    target=${item#*=}
    until check "$kind" "$target"; do
        if [ "$kind" = unit ] && [ "$(systemctl show -P ActiveState "$target")" = failed ]; then
            break
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
            break
        fi
        sleep 2
    done
    check "$kind" "$target" || failed="$failed $kind $target;"
done

[ -z "$failed" ] && exit 0
echo "boot health check failed:$failed" >&2
if [ -e "/sys/firmware/efi/efivars/LoaderBootCountPath-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f" ]; then
    echo "rebooting, so this boot uses up a try" >&2
    systemctl reboot --no-block
fi
exit 1
