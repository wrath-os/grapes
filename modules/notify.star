# Telling someone when something happens to the machine: a generation didn't boot, or an automatic
# upgrade failed. Each event is a target wrath or a module starts; every place in `notify.to` gets
# a unit wanted by the targets of the events it hears, which sends the event as JSON.

EVENTS = {
    "boot_failed": "wrath-boot-failed.target",
    "upgrade_failed": "wrath-upgrade-failed.target",
}

SEND = "/etc/wrath/notify.sh"

# Sends an event as JSON: what happened, on which machine, when, and the machine's status. Usage:
# notify.sh EVENT webhook URL_FILE | notify.sh EVENT command PROGRAM [ARGS...]
SCRIPT = """#!/bin/sh
set -eu
event=$1
how=$2
shift 2
message() {
    /run/system/bin/wrath status --json 2>/dev/null |
        jq -c --arg event "$event" --arg machine "$(hostname)" \\
            --arg at "$(date -u '+%Y-%m-%d %H:%M:%S')" \\
            '{event: $event, machine: $machine, at: $at, status: .}'
}
case $how in
    webhook)
        message | curl -sSf --retry 5 --retry-connrefused -H 'Content-Type: application/json' \\
            --data-binary @- "$(cat "$1")" >/dev/null
        ;;
    command)
        message | "$@"
        ;;
esac
"""

place = types.record(
    kind = option(types.one_of(["webhook", "command"]), required = True),
    url = option(
        types.str,
        optional = True,
        runtime = True,
        doc = "For `webhook`: where the event is posted as JSON. It can be a secret.",
    ),
    command = option(
        types.list(types.str),
        doc = "For `command`: a program and its arguments, given the event as JSON on stdin.",
    ),
    events = option(
        types.set(types.one_of(sorted(EVENTS.keys()))),
        doc = "The events this place hears. Without any, those in `notify.events`.",
    ),
)

def render(ctx: Context) -> None:
    notify = ctx.read("notify")
    if notify["by"] != "machine" or not notify["to"]:
        return
    ctx.package("jq")
    ctx.package("curl")
    ctx.file(SEND, SCRIPT, 0o755)
    for name, to in sorted(notify["to"].items()):
        at = "notify.to." + name
        if to["kind"] == "webhook":
            if "url" not in to:
                ctx.error(at + ".url", "a webhook needs the `url` it posts to")
                continue
            url = "/etc/wrath/notify/%s.url" % name
            ctx.file(url, to["url"], 0o400)
            how = ["webhook", url]
        else:
            if not to["command"]:
                ctx.error(at + ".command", "a command needs the program it runs")
                continue
            how = ["command"] + to["command"]
        for event in sorted(to["events"] or notify["events"] or EVENTS.keys()):
            ctx.unit("wrath-notify-%s-%s.service" % (name, event.replace("_", "-")), {
                "Unit": {
                    "Description": "Tell %s: %s" % (name, event.replace("_", " ")),
                    "Wants": ["network-online.target"],
                    "After": ["network-online.target"],
                },
                "Service": {
                    "Type": "oneshot",
                    "ExecStart": " ".join(["/bin/sh", SEND, event] + how),
                },
                "Install": {"WantedBy": [EVENTS[event]]},
            })

module(
    name = "notify",
    options = {
        "notify": types.record(
            events = option(
                types.set(types.one_of(sorted(EVENTS.keys()))),
                doc = "The events that are sent: `boot_failed`, `upgrade_failed`. Without any, " +
                      "all of them.",
            ),
            by = option(
                types.one_of(["machine", "coordinator", "none"]),
                default = "machine",
                doc = "Who sends them: the machine itself, a fleet's coordinator, or nobody. " +
                      "Without a place to send to, `status` and the login notice still say.",
            ),
            to = option(types.map(place), doc = "Where events go, by a name of your choosing."),
        ),
    },
    render = render,
    configurations = ["system"],
)
