# Networks with systemd-networkd and DNS with systemd-resolved, both of which the base system
# provides. This module only writes their configuration and asks for them to reload or restart
# when it changes: `.link` files for physical ports, `.netdev` files for bonds, VLANs, bridges
# and VRFs, and `.network` files for addresses, routes and what joins what.

NETWORK_DIR = "/etc/systemd/network/"

route = types.record(
    to = option(
        types.str,
        optional = True,
        runtime = True,
        doc = "The destination, such as `2001:db8::/32`. Without one, the default route.",
    ),
    via = option(types.str, optional = True, runtime = True, doc = "The gateway."),
    table = option(
        types.str,
        optional = True,
        doc = "A routing table: a VRF's name, a number, or `main`.",
    ),
    metric = option(types.int, optional = True),
)

rule = types.record(
    table = option(types.str, required = True, doc = "A VRF's name, a number, or `main`."),
    source = option(types.str, optional = True, runtime = True, doc = "Packets from this prefix."),
    to = option(types.str, optional = True, runtime = True, doc = "Packets to this prefix."),
    incoming = option(types.str, optional = True, doc = "Packets arriving on this interface."),
    priority = option(types.int, optional = True),
    family = option(
        types.one_of(["ipv4", "ipv6", "both"]),
        optional = True,
        doc = "Needed only when neither `source` nor `to` says.",
    ),
)

network = types.record(
    match = option(
        types.list(types.str),
        required = True,
        doc = "Interface names to configure; globs like `enp*` work.",
    ),
    dhcp = option(types.one_of(["yes", "no", "ipv4", "ipv6"]), default = "yes"),
    priority = option(
        types.range(0, 99),
        default = 50,
        doc = "Orders the file among others; the first file matching an interface applies.",
    ),
    ipv6_privacy = option(types.bool, default = False, doc = "Use temporary IPv6 addresses."),
    accept_ra = option(types.bool, optional = True, doc = "Accept IPv6 router advertisements."),
    ignore_carrier_loss = option(
        types.str,
        optional = True,
        doc = "How long to keep the configuration when the link drops, such as `3s`.",
    ),
    required_for_online = option(
        types.bool,
        default = True,
        doc = "Whether the machine needs this network to count as online.",
    ),
    addresses = option(
        types.list(types.str),
        runtime = True,
        doc = "Static addresses with their prefix length, such as `2001:db8::10/64`. A machine " +
              "value works, as `${machine.address}/64`.",
    ),
    # Runtime as a whole, so machine values can go in their addresses: an option in a list of
    # records is checked as the list is.
    routes = option(
        types.list(route),
        runtime = True,
        doc = "Static routes, each with `to` (the default route without one), `via`, `table` " +
              "(a VRF's name, a number or `main`) and `metric`.",
    ),
    rules = option(
        types.list(rule),
        runtime = True,
        doc = "Policy routing rules, each with `table` and any of `source`, `to`, `incoming`, " +
              "`priority` and `family`.",
    ),
    vrf = option(types.str, optional = True, doc = "The VRF device this interface belongs to."),
    mtu = option(types.int, optional = True),
    rp_filter = option(
        types.one_of(["strict", "loose", "off"]),
        optional = True,
        doc = "IPv4 reverse path filtering on this interface. The kernel uses the higher of " +
              "this and `net.ipv4.conf.all.rp_filter` (off 0, strict 1, loose 2), so `off` " +
              "needs that off too.",
    ),
    forwarding = option(
        types.bool,
        optional = True,
        doc = "Forward packets arriving on this interface, over IPv4 and IPv6.",
    ),
    sections = types.map(types.map(types.str)),
)

link = types.record(
    match = option(
        types.record(
            names = option(
                types.list(types.str),
                doc = "Names the kernel gave the ports; globs like `enp*` work.",
            ),
            driver = option(types.str, optional = True, doc = "Such as `mlx5_core`."),
            path = option(types.str, optional = True, doc = "Such as `pci-0000:41:00.*`."),
            mac = option(types.str, optional = True, doc = "The port's permanent MAC address."),
        ),
        default = {},
        doc = "Which ports: every one of these that's given has to match.",
    ),
    mtu = option(types.int, optional = True),
    ring_buffers = option(
        types.record(
            rx = option(types.int, optional = True),
            tx = option(types.int, optional = True),
        ),
        default = {},
        doc = "The NIC's receive and transmit ring sizes, as `ethtool -G` sets them.",
    ),
    sections = types.map(types.map(types.str)),
)

DEVICE_KINDS = ["bond", "vlan", "bridge", "vrf", "dummy"]

device = types.record(
    kind = option(types.one_of(DEVICE_KINDS), required = True),
    on = option(
        types.str,
        optional = True,
        doc = "For a VLAN, the interface it's on: a device, a link, or an interface name.",
    ),
    vlan = option(types.range(1, 4094), optional = True, doc = "For a VLAN, its id."),
    table = option(types.int, optional = True, doc = "For a VRF, its routing table."),
    members = option(
        types.list(types.str),
        doc = "For a bond or bridge, what joins it: links, devices, or interface names.",
    ),
    bond = option(
        types.record(
            mode = option(
                types.one_of([
                    "balance-rr", "active-backup", "balance-xor", "broadcast", "802.3ad",
                    "balance-tlb", "balance-alb",
                ]),
                default = "active-backup",
            ),
            lacp_rate = option(types.one_of(["slow", "fast"]), optional = True),
            hash = option(
                types.one_of(["layer2", "layer2+3", "layer3+4", "encap2+3", "encap3+4"]),
                optional = True,
            ),
            miimon = option(types.str, optional = True, doc = "Such as `100ms`."),
        ),
        default = {},
    ),
    mtu = option(types.int, optional = True),
    sections = types.map(types.map(types.str)),
)

DNS_KEYS = {
    "dnssec": "DNSSEC",
    "dns_over_tls": "DNSOverTLS",
    "cache": "Cache",
}

# What systemd's own default `.link` file sets. A `.link` file of ours replaces it for the ports
# it matches, so it says the same, or those ports would lose their predictable names.
LINK_DEFAULTS = {
    "NamePolicy": "keep kernel database onboard slot path",
    "AlternativeNamesPolicy": "database onboard slot path mac",
    "MACAddressPolicy": "persistent",
}

LINK_MATCH = {
    "names": "OriginalName",
    "driver": "Driver",
    "path": "Path",
    "mac": "PermanentMACAddress",
}

RP_FILTER = {"strict": "strict", "loose": "loose", "off": "no"}

FIXED_TABLES = ["default", "main", "local"]

RING_BUFFER_KEYS = {"rx": "RxBufferSize", "tx": "TxBufferSize"}

BOND_KEYS = {
    "lacp_rate": "LACPTransmitRate",
    "hash": "TransmitHashPolicy",
    "miimon": "MIIMonitorSec",
}

ROUTE_KEYS = {"to": "Destination", "via": "Gateway", "metric": "Metric"}

RULE_KEYS = {
    "source": "From",
    "to": "To",
    "incoming": "IncomingInterface",
    "priority": "Priority",
    "family": "Family",
}

def numbered(priority: int, name: str, suffix: str) -> str:
    text = str(priority)
    return NETWORK_DIR + "0" * (2 - len(text)) + text + "-" + name + suffix

def text_of(
        sections: dict[str, typing.Any],
        repeated: list[typing.Any]) -> typing.Any:
    """A systemd file from `sections`, then a section of its own for each of `repeated`, such as
    one `[Route]` per route. It has machine values in it when the settings do."""
    text = formats.systemd(sections)
    for name, keys in repeated:
        text = text + "\n" + formats.systemd({name: keys})
    return text

def add_sections(sections: dict[str, typing.Any], extra: dict[str, typing.Any]) -> None:
    for section, keys in extra.items():
        sections.setdefault(section, {}).update(keys)

def link_match(cfg: dict[str, typing.Any]) -> dict[str, typing.Any]:
    match = {}
    for option, key in LINK_MATCH.items():
        value = cfg["match"].get(option)
        if value:
            match[key] = value
    return match

def render_links(ctx: Context, links: dict[str, typing.Any]) -> list[str]:
    paths = []
    for name, cfg in links.items():
        match = link_match(cfg)
        if not match:
            ctx.error(["networking", "links", name, "match"], "a link matches ports by " +
                      "`names`, `driver`, `path` or `mac`; without any it would match every one")
        settings = dict(LINK_DEFAULTS)
        if "mtu" in cfg:
            settings["MTUBytes"] = cfg["mtu"]
        ring_buffers = cfg["ring_buffers"]
        for option, key in RING_BUFFER_KEYS.items():
            if option in ring_buffers:
                settings[key] = ring_buffers[option]
        sections = {"Match": match, "Link": settings}
        add_sections(sections, cfg["sections"])
        path = numbered(50, name, ".link")
        ctx.file(path, formats.systemd(sections))
        paths.append(path)
    return paths

def check_device(ctx: Context, name: str, cfg: dict[str, typing.Any]) -> None:
    at = ["networking", "devices", name]
    kind = cfg["kind"]
    if len(name) > 15:
        ctx.error(at, "an interface name has at most 15 characters, and `%s` has %d" % (
            name,
            len(name),
        ))
    if kind == "vlan" and ("on" not in cfg or "vlan" not in cfg):
        ctx.error(at, "a VLAN needs `on`, the interface it's on, and `vlan`, its id")
    if kind != "vlan" and ("on" in cfg or "vlan" in cfg):
        ctx.error(at, "only a VLAN has `on` and `vlan`")
    if kind == "vrf" and "table" not in cfg:
        ctx.error(at, "a VRF needs `table`, the routing table its routes go in")
    if kind != "vrf" and "table" in cfg:
        ctx.error(at + ["table"], "only a VRF has a table")
    if cfg["members"] and kind not in ["bond", "bridge"]:
        ctx.error(at + ["members"], "only a bond or a bridge has members")

def netdev(name: str, cfg: dict[str, typing.Any]) -> dict[str, typing.Any]:
    kind = cfg["kind"]
    sections = {"NetDev": {"Name": name, "Kind": kind}}
    if "mtu" in cfg:
        sections["NetDev"]["MTUBytes"] = cfg["mtu"]
    if kind == "bond":
        bond = cfg["bond"]
        sections["Bond"] = {"Mode": bond["mode"]}
        for option, key in BOND_KEYS.items():
            if option in bond:
                sections["Bond"][key] = bond[option]
    elif kind == "vlan":
        sections["VLAN"] = {"Id": cfg["vlan"]}
    elif kind == "vrf":
        sections["VRF"] = {"Table": cfg["table"]}
    add_sections(sections, cfg["sections"])
    return sections

def table_of(ctx: Context, at: list[str], table: str, devices: dict[str, typing.Any]) -> str:
    if type(table) != "string":
        ctx.error(at, "a routing table is fixed when the system is built, so it can't be a " +
                  "machine value")
    device = devices.get(table)
    if device and device["kind"] == "vrf":
        return str(device["table"])
    if table in FIXED_TABLES or table.isdigit():
        return table
    vrfs = sorted([name for name, d in devices.items() if d["kind"] == "vrf"])
    ctx.error(at, "`%s` isn't a routing table: name a VRF (%s), a number, or `main`" % (
        table,
        ", ".join(["`%s`" % name for name in vrfs]) or "there are none",
    ))
    return table

def route_section(
        ctx: Context,
        at: list[str],
        r: dict[str, typing.Any],
        devices: dict[str, typing.Any]) -> dict[str, typing.Any]:
    keys = {key: r[option] for option, key in ROUTE_KEYS.items() if option in r}
    if "table" in r:
        keys["Table"] = table_of(ctx, at, r["table"], devices)
    return keys

def rule_section(
        ctx: Context,
        at: list[str],
        r: dict[str, typing.Any],
        devices: dict[str, typing.Any]) -> dict[str, typing.Any]:
    keys = {"Table": table_of(ctx, at, r["table"], devices)}
    for option, key in RULE_KEYS.items():
        if option in r:
            keys[key] = r[option]
    return keys

def render_network(
        ctx: Context,
        name: str,
        cfg: dict[str, typing.Any],
        attached: dict[str, typing.Any],
        devices: dict[str, typing.Any]) -> str:
    at = ["networking", "networks", name]
    sections = {
        "Match": {"Name": cfg["match"]},
        "Network": {"DHCP": cfg["dhcp"], "IPv6PrivacyExtensions": cfg["ipv6_privacy"]},
    }
    if not cfg["required_for_online"]:
        sections["Link"] = {"RequiredForOnline": False}
    if "mtu" in cfg:
        sections.setdefault("Link", {})["MTUBytes"] = cfg["mtu"]
    network = sections["Network"]
    if "accept_ra" in cfg:
        network["IPv6AcceptRA"] = cfg["accept_ra"]
    if "ignore_carrier_loss" in cfg:
        network["IgnoreCarrierLoss"] = cfg["ignore_carrier_loss"]
    if cfg["addresses"]:
        network["Address"] = cfg["addresses"]
    if "vrf" in cfg:
        vrf = devices.get(cfg["vrf"])
        if not vrf or vrf["kind"] != "vrf":
            ctx.error(at + ["vrf"], "`%s` isn't a VRF under `networking.devices`" % cfg["vrf"])
        network["VRF"] = cfg["vrf"]
    if "rp_filter" in cfg:
        network["IPv4ReversePathFilter"] = RP_FILTER[cfg["rp_filter"]]
    if "forwarding" in cfg:
        network["IPv4Forwarding"] = cfg["forwarding"]
        network["IPv6Forwarding"] = cfg["forwarding"]
    for interface in cfg["match"]:
        network.update(attached.get(interface, {}))
    add_sections(sections, cfg["sections"])
    repeated = [
        ("Route", route_section(ctx, at + ["routes"], r, devices))
        for r in cfg["routes"]
    ] + [
        ("RoutingPolicyRule", rule_section(ctx, at + ["rules"], r, devices))
        for r in cfg["rules"]
    ]
    path = numbered(cfg["priority"], name, ".network")
    # networkd reads its files as its own user, so they're readable by anyone, machine values
    # filled in or not.
    ctx.file(path, text_of(sections, repeated), 420)
    return path

def attachments(devices: dict[str, typing.Any]) -> dict[str, typing.Any]:
    """What each interface joins, by its name: the VLANs on it, and the bond, bridge or VRF it's
    a member of, as its `.network` file says them."""
    attached = {}
    for name, cfg in devices.items():
        if cfg["kind"] == "vlan":
            attached.setdefault(cfg["on"], {}).setdefault("VLAN", []).append(name)
        for member in cfg["members"]:
            attached.setdefault(member, {})[cfg["kind"].capitalize()] = name
    return attached

def render_devices(
        ctx: Context,
        devices: dict[str, typing.Any],
        links: dict[str, typing.Any],
        attached: dict[str, typing.Any],
        named: dict[str, bool]) -> list[str]:
    """The devices' `.netdev` files, and a `.network` file for each interface that joins one
    and that no network names. A device no network names gets one too, or networkd would leave
    it down."""
    paths = []
    for name, cfg in devices.items():
        path = numbered(50, name, ".netdev")
        ctx.file(path, formats.systemd(netdev(name, cfg)))
        paths.append(path)
    unnamed = {i: True for i in list(attached) + list(devices) if i not in named}
    for interface in sorted(unnamed):
        match = link_match(links[interface]) if interface in links else {"Name": interface}
        path = numbered(40, interface, ".network")
        ctx.file(path, formats.systemd({
            "Match": match,
            "Network": dict(attached.get(interface, {}), LinkLocalAddressing = False),
            "Link": {"RequiredForOnline": False},
        }))
        paths.append(path)
    return paths

def render_loopback(ctx: Context, addresses: list[typing.Any]) -> str:
    path = numbered(10, "loopback", ".network")
    ctx.file(path, formats.systemd({
        "Match": {"Name": "lo"},
        "Network": {"Address": ["127.0.0.1/8", "::1/128"] + addresses},
    }), 420)
    return path

def render(ctx: Context) -> None:
    networks = ctx.read("networking.networks")
    links = ctx.read("networking.links")
    devices = ctx.read("networking.devices")
    for name, cfg in devices.items():
        check_device(ctx, name, cfg)
    if any([d["kind"] == "bond" for d in devices.values()]):
        # Loading the bonding driver otherwise makes a `bond0` with its defaults, which networkd
        # then joins ports to without setting its mode.
        ctx.set("kernel.module_options", {"bonding": "max_bonds=0"})
    attached = attachments(devices)
    named = {interface: True for n in networks.values() for interface in n["match"]}
    paths = render_devices(ctx, devices, links, attached, named)
    paths += [render_network(ctx, name, cfg, attached, devices) for name, cfg in networks.items()]
    loopback = ctx.read("networking.loopback")
    if loopback["addresses"]:
        paths.append(render_loopback(ctx, loopback["addresses"]))
    if paths:
        # New devices appear and networks change at a reload. A device that exists keeps the
        # settings of its kind, such as a bond's mode, until it's made again, at the next boot.
        ctx.reload("systemd-networkd.service", on = paths)
        # Interfaces get only the networks configured here.
        ctx.default("networking.dhcp", False)

    link_paths = render_links(ctx, links)
    if link_paths:
        # udev applies `.link` files as ports appear. Asking it again applies a change to the
        # ports there are: MTU and ring sizes now, names only when a port next appears.
        ctx.unit("network-links.service", {
            "Unit": {
                "Description": "Link settings for the network ports there are",
                "After": "systemd-udev-trigger.service",
            },
            "Service": {
                "Type": "oneshot",
                "RemainAfterExit": "yes",
                "ExecStart": "/run/system/bin/udevadm trigger --subsystem-match=net " +
                             "--action=add",
            },
            "Install": {"WantedBy": "multi-user.target"},
        }, restart_on = link_paths)

    dns = ctx.read("networking.dns")
    resolve = {key: dns[option] for option, key in DNS_KEYS.items() if option in dns}
    if dns["fallback"]:
        resolve["FallbackDNS"] = " ".join(dns["fallback"])
    if resolve:
        path = "/etc/systemd/resolved.conf.d/wrath.conf"
        ctx.file(path, formats.systemd({"Resolve": resolve}))
        ctx.restart("systemd-resolved.service", on = [path])
        ctx.set("networking.resolved", True)

module(
    name = "network",
    options = {
        "networking.networks": types.map(network),
        "networking.links": option(
            types.map(link),
            doc = "Settings for physical ports, matched by what they are, such as their driver.",
        ),
        "networking.devices": option(
            types.map(device),
            doc = "Interfaces made in software, by name: bonds, VLANs, bridges, VRFs and dummies.",
        ),
        "networking.loopback": types.record(
            addresses = option(
                types.list(types.str),
                runtime = True,
                doc = "Addresses on `lo` besides its own, such as `fd00::1/128` for a service " +
                      "announced over BGP.",
            ),
        ),
        "networking.dns": types.record(
            fallback = option(
                types.list(types.str),
                doc = "Servers to use when no network provides one.",
            ),
            dnssec = option(types.one_of(["yes", "no", "allow-downgrade"]), optional = True),
            dns_over_tls = option(types.one_of(["yes", "no", "opportunistic"]), optional = True),
            cache = option(types.one_of(["yes", "no", "no-negative"]), optional = True),
        ),
    },
    render = render,
)
