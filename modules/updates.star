# Where machines running this configuration upgrade from, and upgrading from there on a timer.
# wrath reads `updates.from` from the running system: `wrath apply` with no configuration given
# fetches the newest commit there.

SCHEMES = ["github:", "https://", "path:"]

def render(ctx: Context) -> None:
    source = ctx.read("updates.from")
    if source and not any([source.startswith(scheme) for scheme in SCHEMES]):
        ctx.error(
            "updates.from",
            "machines upgrade from `github:owner/repo//dir`, an `https://` archive or `path:DIR`",
        )
    when = ctx.read("updates.automatic")
    if not when:
        return
    if not source:
        ctx.error("updates.automatic", "upgrading on its own needs `updates.from` to upgrade from")
        return
    ctx.unit("wrath-upgrade.service", {
        "Unit": {
            "Description": "Upgrade from " + source,
            "Wants": ["network-online.target"],
            "After": ["network-online.target"],
        },
        "Service": {
            "Type": "oneshot",
            # The running system's own wrath, which a switch moves on with it.
            "ExecStart": "/run/system/bin/wrath apply --automatic",
        },
    })
    ctx.unit("wrath-upgrade.timer", {
        "Unit": {"Description": "Upgrade from " + source + " " + when},
        "Timer": {
            "OnCalendar": when,
            # Machines on one repository don't all fetch at once, and each keeps its own time.
            "RandomizedDelaySec": "1h",
            "FixedRandomDelay": True,
            # A machine that was off at the time upgrades when it's back.
            "Persistent": True,
        },
        "Install": {"WantedBy": ["timers.target"]},
    })

module(
    name = "updates",
    options = {
        "updates.from": option(
            types.str,
            optional = True,
            doc = "Where machines running this configuration upgrade from, such as " +
                  "`github:owner/repo//dir`. `wrath apply` with no configuration given " +
                  "fetches the newest commit there.",
        ),
        "updates.automatic": option(
            types.str,
            optional = True,
            doc = "When to upgrade from `updates.from` on its own, as a systemd calendar time " +
                  "such as `daily`, spread over an hour so machines don't all fetch at once.",
        ),
        "updates.switch": option(
            types.one_of(["auto", "now", "boot"]),
            default = "auto",
            doc = "What an automatic upgrade does: `now` switches, `boot` makes it the " +
                  "system booted next, and `auto` switches when every change takes effect " +
                  "live or at the next login, and otherwise waits for the next boot.",
        ),
        "updates.token": option(
            types.path,
            optional = True,
            runtime = True,
            doc = "A GitHub token that can read `updates.from`, and the private sources its " +
                  "lock pins, such as `{ secret = \"github-token\" }`. Without it, upgrades " +
                  "use `GH_TOKEN` or the token `gh` is logged in with.",
        ),
        "updates.build": option(
            types.bool,
            default = True,
            doc = "Whether an automatic upgrade builds what no cache has. With `false` it " +
                  "waits, and upgrades once a cache has everything, which suits a machine " +
                  "that builds slowly or can't build at all.",
        ),
    },
    render = render,
    configurations = ["system"],
)
