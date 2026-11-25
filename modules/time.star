# Keeping the clock right: systemd-timesyncd asks time servers over the network. Without it the
# clock is only as good as the machine's battery-backed one, which drifts.

CONF = "/etc/systemd/timesyncd.conf.d/wrath.conf"

# The public NTP pool, used when neither the configuration nor the network names servers.
POOL = ["0.pool.ntp.org", "1.pool.ntp.org", "2.pool.ntp.org", "3.pool.ntp.org"]

def render(ctx: Context) -> None:
    time = ctx.read("time")
    if not time["sync"]:
        return
    settings = {"FallbackNTP": " ".join(POOL)}
    if time["servers"]:
        settings["NTP"] = " ".join(time["servers"])
    ctx.file(CONF, formats.systemd({"Time": settings}))
    ctx.enable("systemd-timesyncd.service")
    ctx.restart("systemd-timesyncd.service", on = [CONF])

module(
    name = "time",
    options = {
        "time": types.record(
            sync = option(
                types.bool,
                default = True,
                doc = "Whether the clock is set from time servers over the network.",
            ),
            servers = option(
                types.list(types.str),
                doc = "The time servers it asks, such as `ntp.example.com`. Without any, those " +
                      "the network hands out over DHCP, and then the public NTP pool.",
            ),
        ),
    },
    render = render,
    configurations = ["system"],
)
