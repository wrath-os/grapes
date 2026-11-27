# What a good boot takes, and what happens after a bad one. The boot loader gives each new
# generation a few tries; a boot counts as good once it reaches `boot-complete.target`. The checks
# here gate that target, and a boot that fails one or doesn't get there in time reboots, using up
# a try, so a generation that can't serve ends with the machine on the last good one. A boot that
# fell back makes the generation that runs current, keeps a record of it, and starts
# `wrath-boot-failed.target`, which notifiers hang on.

load("lib/durations.star", "seconds")

HEALTH = "/etc/wrath/boot-health.sh"
FALLBACK = "/etc/wrath/boot-fallback.sh"

# Where the boot loader says it counts tries for this boot. Without it the generation booted is
# one already known good, or the machine doesn't count tries, and a failed check reboots nothing.
COUNTING = "/sys/firmware/efi/efivars/LoaderBootCountPath-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"

# Runs each check until all pass or the time runs out. A failure on a boot the boot loader counts
# reboots, using up a try. Usage: boot-health.sh SECONDS CHECKS_JSON
CHECK = """#!/bin/sh
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
for item in $(jq -r '.[] | "\\(.kind)=\\(.target)"' "$checks"); do
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
if [ -e "@COUNTING@" ]; then
    echo "rebooting, so this boot uses up a try" >&2
    systemctl reboot --no-block
fi
exit 1
""".replace("@COUNTING@", COUNTING)

# Makes the generation that runs current when the boot loader gave up on the current one, which
# keeps a record of it, and starts the target notifiers hang on.
FALLBACK_SCRIPT = """#!/bin/sh
set -eu
# Without a configuration it can read, wrath still says what it knows about the machine.
status=$(/run/system/bin/wrath status --json 2>/dev/null) || true
failed=$(printf '%s\\n' "$status" | sed -n '/"boot_failed": {/,/}/p')
# Only while the generation that failed is still current: rolled back, it has a time.
case $failed in *'"at": null'*) ;; *) exit 0 ;; esac
runs=$(printf '%s\\n' "$failed" | sed -n 's/.*"runs": \\([0-9]*\\).*/\\1/p')
/run/system/bin/wrath rollback "$runs"
systemctl start --no-block wrath-boot-failed.target
"""

def checks_of(health: dict[str, typing.Any]) -> list[dict[str, str]]:
    checks = [{"kind": "unit", "target": unit} for unit in sorted(health["checks"])]
    for kind in ["ping", "resolve", "tcp", "http"]:
        checks += [{"kind": kind, "target": target} for target in health[kind]]
    return checks

def render(ctx: Context) -> None:
    health = ctx.read("boot.health")
    watchdog = ctx.read("boot.watchdog")
    within = seconds(ctx, "boot.health.within", health["within"])
    checks = checks_of(health)

    if watchdog:
        ctx.file("/etc/systemd/system.conf.d/watchdog.conf", formats.systemd({
            "Manager": {"RuntimeWatchdogSec": watchdog, "RebootWatchdogSec": "10min"},
        }))

    # The fallback runs on every boot: a fallback is noticed whether or not anything is checked.
    ctx.file(FALLBACK, FALLBACK_SCRIPT, 0o755)
    ctx.unit("wrath-boot-failed.target", {
        "Unit": {"Description": "A generation didn't boot and an older one runs"},
    })
    ctx.unit("wrath-boot-fallback.service", {
        "Unit": {
            "Description": "Make the generation that runs current after a boot that fell back",
            "After": ["multi-user.target"],
        },
        "Service": {"Type": "oneshot", "ExecStart": "/bin/sh " + FALLBACK},
        "Install": {"WantedBy": "multi-user.target"},
    })

    gates = ["systemd-boot-check-no-failures.service"] if health["no_failed_units"] else []
    if checks:
        gates.append("wrath-boot-health.service")
    if not gates:
        return
    # The boot loader counts this boot: it needs what gates it, and has `within` to get there,
    # or it reboots.
    ctx.unit("boot-complete.target.d/wrath.conf", {
        "Unit": {
            "Requires": gates,
            "After": gates,
            "JobTimeoutSec": health["within"],
            "JobTimeoutAction": "reboot-force",
        },
    })
    if not checks:
        return
    ctx.package("curl")
    ctx.package("iputils")
    ctx.file("/etc/wrath/boot-health.json", formats.json(checks))
    ctx.file(HEALTH, CHECK, 0o755)
    units = [c["target"] for c in checks if c["kind"] == "unit"]
    after = units + (["network-online.target"] if len(units) < len(checks) else [])
    ctx.unit("wrath-boot-health.service", {
        "Unit": {
            "Description": "Check this boot is good before the boot loader counts it",
            "Wants": after,
            "After": after,
            "Before": ["boot-complete.target"],
        },
        "Service": {
            "Type": "oneshot",
            "RemainAfterExit": "yes",
            "ExecStart": "/bin/sh %s %d /etc/wrath/boot-health.json" % (HEALTH, within),
            "TimeoutStartSec": "infinity",
        },
    })

module(
    name = "boot-health",
    options = {},
    render = render,
    configurations = ["system"],
)
