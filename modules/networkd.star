# Networking: systemd-networkd, and DHCP on every wired interface
# unless the configuration describes its networks.

def render(ctx: Context) -> None:
    dhcp = ctx.read("networking.dhcp")
    resolved = ctx.read("networking.resolved")
    if dhcp:
        ctx.file("/etc/systemd/network/99-dhcp.network", formats.systemd({
            "Match": {"Type": "ether", "Kind": "!*"},
            "Network": {"DHCP": "yes"},
        }))
    if dhcp or ctx.read("networking.networks"):
        ctx.enable("systemd-networkd.service")
        ctx.enable("systemd-networkd-wait-online.service")
        ctx.enable("network-online.target", wanted_by = "multi-user.target")
        # DHCP on whichever port has a cable, and wifi, are networks the machine uses one of:
        # it's online once any is. Networks described one by one are each needed, unless
        # they say otherwise, and it's online once every one is.
        online = ctx.read("networking.online") or ("any" if dhcp else "all")
        if online == "any":
            ctx.unit("systemd-networkd-wait-online.service.d/wrath.conf", {
                "Service": {
                    "ExecStart": [
                        "",
                        "/run/system/systemd/lib/systemd/systemd-networkd-wait-online --any",
                    ],
                },
            })
    if resolved:
        ctx.enable("systemd-resolved.service")

module(
    name = "networkd",
    options = {
        "networking.online": option(
            types.one_of(["all", "any"]),
            optional = True,
            doc = "When the machine counts as online, for what waits for the network: once `all` " +
                  "the networks it needs are up, or `any` one of them. The default is `any` with " +
                  "DHCP on every wired interface, and `all` with networks described one by one.",
        ),
    },
    render = render,
)
