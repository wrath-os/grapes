# Nushell for each user who has it as their login shell or enables it:
# `~/.config/nushell/config.nu`, with settings merged into its own, aliases and lines of their own.

load("lib/environment.star", "nu_line")

def config_nu(nu: dict[str, typing.Any], environment: dict[str, str]) -> str:
    lines = ["# Written by wrath from the configuration; changes here are replaced."]
    # The user's `environment`, which a login gets from PAM only system-wide; other shells read it
    # from what POSIX shells source.
    lines += [nu_line(name, value) for name, value in sorted(environment.items())]
    if nu["settings"]:
        # JSON is a Nushell record as it's written, so the settings go in as they are.
        settings = formats.json(nu["settings"]).strip()
        lines.append("$env.config = ($env.config | merge deep %s)" % settings)
    lines += ["alias %s = %s" % (name, value) for name, value in sorted(nu["aliases"].items())]
    text = "".join([line + "\n" for line in lines])
    return text + nu["init"] if nu["init"] else text

def render(ctx: Context) -> None:
    for user, u in ctx.read("users").items():
        nu = u["programs"]["nushell"]
        if not (nu["enable"] or u.get("shell") == "nushell"):
            continue
        ctx.file("~/.config/nushell/config.nu", config_nu(nu, u["environment"]), user = user)
        ctx.package("nushell", user = user)

module(
    name = "nushell",
    options = {},
    user_options = {
        "programs.nushell": types.record(
            enable = option(
                types.bool,
                default = False,
                doc = "Nushell with these settings for a user whose login shell is another.",
            ),
            settings = option(
                types.freeform,
                default = {},
                doc = "Nushell's own settings, as in `$env.config`, such as `show_banner = false`.",
            ),
            aliases = option(
                types.map(types.str),
                default = {},
                doc = "Aliases by name, such as `{ ll = \"ls -l\" }`.",
            ),
            init = option(
                types.str,
                default = "",
                doc = "Lines of Nushell run after the rest, in every Nushell.",
            ),
        ),
    },
    writes = [],
    render = render,
    configurations = ["system"],
)
