#!/bin/sh
set -eu
# Without a configuration it can read, wrath still says what it knows about the machine.
status=$(/run/system/bin/wrath status --json 2>/dev/null) || true
failed=$(printf '%s\n' "$status" | sed -n '/"boot_failed": {/,/}/p')
# Only while the generation that failed is still current: rolled back, it has a time.
case $failed in *'"at": null'*) ;; *) exit 0 ;; esac
runs=$(printf '%s\n' "$failed" | sed -n 's/.*"runs": \([0-9]*\).*/\1/p')
/run/system/bin/wrath rollback "$runs"
systemctl start --no-block wrath-boot-failed.target
