# A host firewall, rendered as an nftables ruleset in a table of its own. Other tables, such as
# tailscale's or a container runtime's, are left alone, and a change replaces this one in a single
# step. Zones open ports on some interfaces or to some sources; the flat options open them
# everywhere.

TABLE = "inet wrath"
CONFIG = "/etc/nftables.conf"
TABLES_DIR = "/etc/nftables.d/"

# What IPv6 needs to work at all: finding neighbours and routers, and hearing that a packet was too
# big, which path MTU discovery relies on.
ICMPV6 = [
    "destination-unreachable", "packet-too-big", "time-exceeded", "parameter-problem",
    "nd-router-solicit", "nd-router-advert", "nd-neighbor-solicit", "nd-neighbor-advert",
]
ICMP = ["destination-unreachable", "time-exceeded", "parameter-problem"]

# Sources that never arrive honestly from the internet: private, shared, loopback, link-local,
# documentation, benchmarking, multicast and reserved ranges. IPv6 link-local stays allowed, since
# neighbour discovery comes from it.
SPOOFED_IPV4 = [
    "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12",
    "192.0.0.0/24", "192.0.2.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24",
    "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4",
]
SPOOFED_IPV6 = [
    "::/128", "::1/128", "::ffff:0:0/96", "100::/64", "2001:db8::/32", "3fff::/20", "fc00::/7",
    "ff00::/8",
]

TABLE_FAMILIES = ["ip", "ip6", "inet", "arp", "bridge", "netdev"]

CLAMP_FAMILY = {"ipv4": "meta nfproto ipv4 ", "ipv6": "meta nfproto ipv6 ", "both": ""}

zone = types.record(
    interfaces = option(
        types.set(types.str),
        doc = "The interfaces in the zone; globs like `br*` work. Without any, every interface.",
    ),
    tcp = option(
        types.set(types.freeform),
        doc = "TCP ports open in the zone: numbers, or ranges such as `\"30000-32767\"`.",
    ),
    udp = option(types.set(types.freeform), doc = "UDP ports open in the zone, as `tcp` is."),
    sources = option(
        types.set(types.str),
        doc = "Prefixes the zone's ports are open to, such as `2001:db8:100::/56`. Without " +
              "any, every source.",
    ),
    drop_spoofed = option(
        types.bool,
        default = False,
        doc = "Drop packets arriving on the zone's interfaces from private, documentation and " +
              "other ranges no internet host has, before anything else sees them. For an " +
              "interface facing the internet with public addresses on the far side.",
    ),
)

forward = types.record(
    source = option(types.str, required = True, doc = "A zone, or an interface."),
    to = option(types.str, required = True, doc = "A zone, or an interface."),
)

clamp = types.record(
    out = option(types.str, required = True, doc = "The interface packets leave by."),
    mss = option(
        types.int,
        optional = True,
        doc = "The largest segment size. Without one, what the route's MTU allows.",
    ),
    family = option(types.one_of(["ipv4", "ipv6", "both"]), default = "both"),
)

def quoted(names: list[str]) -> list[str]:
    return ["\"%s\"" % name for name in names]

def port_text(ctx: Context, at: list[str], port: typing.Any) -> str:
    if type(port) == "int" and port >= 1 and port <= 65535:
        return str(port)
    if type(port) == "string":
        bounds = port.split("-")
        if len(bounds) == 2 and bounds[0].isdigit() and bounds[1].isdigit():
            low, high = int(bounds[0]), int(bounds[1])
            if low >= 1 and low < high and high <= 65535:
                return "%d-%d" % (low, high)
    ctx.error(at, "`%s` isn't a port or a range of ports such as `30000-32767`" % port)
    return ""

def ports_rule(ctx: Context, at: list[str], protocol: str, ports: list[typing.Any]) -> str:
    texts = [port_text(ctx, at, port) for port in ports]
    if len(texts) == 1:
        return "%s dport %s accept" % (protocol, texts[0])
    return "%s dport { %s } accept" % (protocol, ", ".join(texts))

def by_family(prefixes: list[str]) -> list[str]:
    """Matches for `prefixes` as sources, one per address family that has any."""
    ipv4 = [prefix for prefix in prefixes if ":" not in prefix]
    ipv6 = [prefix for prefix in prefixes if ":" in prefix]
    matches = []
    if ipv4:
        matches.append("ip saddr { %s }" % ", ".join(ipv4))
    if ipv6:
        matches.append("ip6 saddr { %s }" % ", ".join(ipv6))
    return matches

def zone_rules(ctx: Context, name: str, z: dict[str, typing.Any]) -> list[str]:
    at = ["networking", "firewall", "zones", name]
    accepts = []
    for protocol in ["tcp", "udp"]:
        if z[protocol]:
            accepts.append(ports_rule(ctx, at + [protocol], protocol, z[protocol]))
    interfaces = ["iifname \"%s\"" % i for i in z["interfaces"]] or [""]
    sources = by_family(z["sources"]) or [""]
    rules = []
    for interface in interfaces:
        for source in sources:
            rules += ["    " + " ".join([part for part in [interface, source, accept] if part])
                      for accept in accepts]
    return rules

def interfaces_of(zones: dict[str, typing.Any], name: str) -> list[str]:
    """The interfaces a zone, or an interface by its name, stands for. An empty list means any."""
    if name in zones:
        return zones[name]["interfaces"]
    return [name]

def forward_chain(firewall: dict[str, typing.Any]) -> list[str]:
    rules = [
        "  chain forward {",
        "    type filter hook forward priority 0; policy drop;",
        "    ct state established,related accept",
        "    ct state invalid drop",
    ]
    for pair in firewall["forward"]:
        for source in interfaces_of(firewall["zones"], pair["source"]) or [""]:
            for to in interfaces_of(firewall["zones"], pair["to"]) or [""]:
                parts = []
                if source:
                    parts.append("iifname \"%s\"" % source)
                if to:
                    parts.append("oifname \"%s\"" % to)
                rules.append("    %s accept" % " ".join(parts))
    return rules + ["  }"]

def clamp_chain(clamps: list[typing.Any]) -> list[str]:
    rules = [
        "  chain clamp {",
        "    type filter hook forward priority mangle; policy accept;",
    ]
    for c in clamps:
        family = CLAMP_FAMILY[c["family"]]
        size = str(c["mss"]) if "mss" in c else "rt mtu"
        rules.append(
            "    oifname \"%s\" %stcp flags & (syn | rst) == syn tcp option maxseg size set %s" % (
                c["out"],
                family,
                size,
            ),
        )
    return rules + ["  }"]

def spoof_chain(ctx: Context, zones: dict[str, typing.Any]) -> list[str]:
    interfaces = []
    for name, z in zones.items():
        if z["drop_spoofed"]:
            if not z["interfaces"]:
                ctx.error(
                    ["networking", "firewall", "zones", name, "drop_spoofed"],
                    "dropping spoofed sources needs the zone's `interfaces`: on every " +
                    "interface it would drop the loopback's and the local network's own",
                )
            interfaces += z["interfaces"]
    if not interfaces:
        return []
    # Before connection tracking, so spoofed packets cost as little as possible.
    rules = [
        "  chain spoofed {",
        "    type filter hook prerouting priority raw; policy accept;",
    ]
    for interface in sorted(interfaces):
        rules.append("    iifname \"%s\" ip saddr { %s } drop" % (
            interface,
            ", ".join(SPOOFED_IPV4),
        ))
        rules.append("    iifname \"%s\" ip6 saddr { %s } drop" % (
            interface,
            ", ".join(SPOOFED_IPV6),
        ))
    return rules + ["  }"]

def own_tables(ctx: Context, tables: dict[str, typing.Any]) -> list[str]:
    """Writes each table of the configuration's own beside the module's, emptied before it's
    loaded, so loading it again replaces it. Returns where they are."""
    paths = []
    for key, t in tables.items():
        words = key.split(" ")
        if len(words) != 2 or words[0] not in TABLE_FAMILIES or key == TABLE:
            ctx.error(
                ["networking", "firewall", "tables", key],
                "name a table by its family and name, such as `inet filter`, with the family " +
                "one of %s; `%s` is the firewall's own" % (", ".join(TABLE_FAMILIES), TABLE),
            )
        path = TABLES_DIR + "-".join(words) + ".nft"
        ctx.file(path, "table %s\nflush table %s\n" % (key, key) + t["file"])
        paths.append(path)
    return paths

def render(ctx: Context) -> None:
    firewall = ctx.read("networking.firewall")
    zones = firewall["zones"]
    icmp, icmpv6 = list(ICMP), list(ICMPV6)
    if firewall["allow_ping"]:
        icmp.append("echo-request")
        icmpv6.append("echo-request")
    rules = [
        # Declared and emptied first, so loading the file replaces the table in one step.
        "table %s" % TABLE,
        "flush table %s" % TABLE,
        "table %s {" % TABLE,
        "  chain input {",
        "    type filter hook input priority 0; policy drop;",
        "    ct state established,related accept",
        "    ct state invalid drop",
        "    iif lo accept",
        "    icmp type { %s } accept" % ", ".join(icmp),
        "    icmpv6 type { %s } accept" % ", ".join(icmpv6),
        # Replies from a DHCPv6 server, which come from its port to the client's link-local one.
        "    ip6 daddr fe80::/64 udp sport 547 udp dport 546 accept",
    ]
    for name in firewall["trusted_interfaces"]:
        rules.append("    iifname \"%s\" accept" % name)
    for port in firewall["allowed_tcp_ports"]:
        rules.append("    tcp dport %d accept" % port)
    for port in firewall["allowed_udp_ports"]:
        rules.append("    udp dport %d accept" % port)
    for name, z in zones.items():
        rules += zone_rules(ctx, name, z)
    rules.append("  }")
    if firewall["forward"]:
        rules += forward_chain(firewall)
    if firewall["clamp_mss"]:
        rules += clamp_chain(firewall["clamp_mss"])
    rules += spoof_chain(ctx, zones)
    rules.append("}")
    tables = own_tables(ctx, firewall["tables"])
    rules += ["include \"%s\"" % path for path in tables]
    ctx.package("nftables")
    ctx.file(CONFIG, lines(rules))
    apply = "nft -f " + CONFIG
    ctx.unit("nftables.service", {
        "Unit": {"Description": "nftables firewall", "Before": "network-pre.target"},
        "Service": {
            "Type": "oneshot",
            "RemainAfterExit": "yes",
            "ExecStart": apply,
            "ExecReload": apply,
            "ExecStop": ["nft delete table " + TABLE] + [
                "-nft delete table " + key
                for key in sorted(firewall["tables"])
            ],
        },
        "Install": {"WantedBy": "multi-user.target"},
    })
    # A changed ruleset is loaded over the old one, so there's never a moment with no rules. A
    # table of the configuration's own that's taken away stays loaded until the next boot.
    ctx.reload("nftables.service", on = [CONFIG] + tables)

module(
    name = "firewall",
    options = {
        "networking.firewall": types.record(
            allowed_tcp_ports = option(types.set(types.port)),
            allowed_udp_ports = option(types.set(types.port)),
            trusted_interfaces = option(
                types.set(types.str),
                doc = "Interfaces whose traffic is always accepted, such as a VPN's.",
            ),
            allow_ping = option(
                types.bool,
                default = True,
                doc = "Answer pings, over IPv4 and IPv6.",
            ),
            zones = option(
                types.map(zone),
                doc = "Ports open on some interfaces, or to some sources, by the zone's name.",
            ),
            forward = option(
                types.list(forward),
                doc = "Forwarding allowed from a zone or interface to another, each as " +
                      "`{ source = ..., to = ... }`; replies are allowed back. With any, " +
                      "everything else forwarded through the machine is dropped, so a " +
                      "container runtime's forwarding needs a pair too.",
            ),
            clamp_mss = option(
                types.list(clamp),
                doc = "TCP connections forwarded out of an interface have their segment size " +
                      "clamped, each as `{ out = ..., mss = ..., family = ... }`, for links " +
                      "with a smaller MTU on the way.",
            ),
            tables = option(
                types.map(types.record(file = option(types.file, required = True))),
                doc = "nftables tables of the configuration's own, by family and name, such as " +
                      "`\"inet prefilter\" = { file = \"nft/prefilter.nft\" }`, loaded with the " +
                      "firewall's.",
            ),
        ),
    },
    enable = True,
    render = render,
)
