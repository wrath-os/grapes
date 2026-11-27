# The base system: boot, networking, audio and the graphical session. wrath builds
# these from the base settings this module works out: the kernel's command line, and what the
# options say.

load("lib/durations.star", "seconds")

# The label of the root filesystem wrath's images have, which a system without disks of its own
# boots from.
ROOT_LABEL = "wrath-root"

# Where the booted generation's firmware is, which the kernel reads before /etc is there.
FIRMWARE = "/run/system-booted/firmware"

# What a boot needs before the boot loader counts it as good; boot-health renders it.
health = types.record(
    checks = option(
        types.set(types.str),
        doc = "Units that must be running, or have finished without failing, for a boot to " +
              "count as good.",
    ),
    ping = option(types.list(types.str), doc = "Hosts that must answer a ping."),
    resolve = option(types.list(types.str), doc = "Names that must resolve."),
    tcp = option(
        types.list(types.str),
        doc = "Addresses as `host:port` that must accept a connection.",
    ),
    http = option(types.list(types.str), doc = "URLs that must answer with success."),
    no_failed_units = option(types.bool, default = False, doc = "Any failed unit fails the boot."),
    within = option(
        types.str,
        default = "15min",
        doc = "How long a boot has to pass its checks before it reboots and uses up a try.",
    ),
)

def kernel_params(ctx: Context, boot: dict[str, typing.Any]) -> list[str]:
    """The kernel's command line. With disks of its own, the initrd mounts the root from them, so
    it isn't named; without, or as the system an image boots, it's the image's root filesystem,
    by its label."""
    params = []
    if ctx.read("image.live") or (not ctx.read("disks") and not ctx.read("filesystems")):
        params = ["root=LABEL=" + ROOT_LABEL, "rw"]
    params += boot["kernel_params"]
    # A panic reboots, so a boot that panics uses up a try.
    panic = boot["reboot_after_panic"]
    if panic:
        params.append("panic=%d" % seconds(ctx, "boot.reboot_after_panic", panic))
    if ctx.read("hardware")["firmware"]:
        params.append("firmware_class.path=" + FIRMWARE)
    return params

def render(ctx: Context) -> None:
    boot = ctx.read("boot")
    ctx.base("boot", {
        "loader": boot["loader"],
        "kernel_params": kernel_params(ctx, boot),
        "secure_boot": boot["secure_boot"],
    })
    if boot["secure_boot"]:
        # The switch decrypts the machine's Secure Boot keys with it.
        ctx.package("age")
    ctx.base("networking", {
        "dhcp": ctx.read("networking.dhcp"),
        "resolved": ctx.read("networking.resolved"),
    })
    ctx.base("audio", {"enable": ctx.read("audio.enable")})

    desktop = ctx.read("desktop")
    if "session" not in desktop:
        return
    session = {"name": desktop["session"]}
    if "autologin" in desktop:
        user = desktop["autologin"]
        if user not in ctx.read("users"):
            ctx.error("desktop.autologin", "there is no user `%s`" % user)
        session["autologin"] = user
    ctx.base("session", session)

module(
    name = "base",
    options = {
        "boot": types.record(
            loader = option(types.one_of(["systemd-boot"]), default = "systemd-boot"),
            kernel_params = option(types.list(types.str)),
            secure_boot = option(
                types.bool,
                default = False,
                doc = "Sign what the machine boots with its own keys, which `wrath secret machine` " +
                      "makes, and enroll them when its firmware is in setup mode.",
            ),
            health = option(health, default = {}),
            watchdog = option(
                types.str,
                optional = True,
                doc = "Have the hardware watchdog reset a machine that hangs this long, such as " +
                      "`30s`.",
            ),
            reboot_after_panic = option(
                types.str,
                default = "10s",
                doc = "Reboot this long after a kernel panic, so the boot uses up a try. Empty " +
                      "to wait.",
            ),
        ),
        "networking.dhcp": option(
            types.bool,
            default = True,
            doc = "Configure every wired interface with DHCP.",
        ),
        "networking.resolved": option(
            types.bool,
            default = True,
            doc = "Run systemd-resolved for DNS, which `/etc/resolv.conf` points at.",
        ),
        "audio.enable": option(types.bool, default = False, doc = "Run PipeWire for users."),
        "desktop": types.record(
            session = option(
                types.one_of(["niri"]),
                optional = True,
                doc = "The graphical session greetd starts.",
            ),
            autologin = option(
                types.str,
                optional = True,
                doc = "Start the session for this user at boot without a login.",
            ),
            shell = option(
                types.one_of(["noctalia"]),
                optional = True,
                doc = "The desktop shell around the compositor: its bar, launcher, " +
                      "notifications and lock screen.",
            ),
        ),
    },
    render = render,
)
