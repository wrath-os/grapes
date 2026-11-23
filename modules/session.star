# Environment variables for each user's sessions, from `environment`: systemd's user manager and
# graphical sessions read `~/.config/environment.d`, and login shells source
# `~/.config/wrath/session.sh`.

load("lib/environment.star", "fish_line")

def check(ctx: Context, user: str, name: str, v: str) -> None:
    where = ["users", user, "environment", name]
    if "\n" in v:
        ctx.error(where, "a value can't span lines")
    if "$(" in v or "`" in v:
        ctx.error(where, "a value can refer to variables as `$NAME`, but can't run commands")

def sh_quote(v: str) -> str:
    """Double quotes, so `$NAME` still expands as it does in environment.d."""
    return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')

def render(ctx: Context) -> None:
    for user, u in ctx.read("users").items():
        variables = u["environment"]
        if not variables:
            continue
        conf = []
        sh = []
        for name, v in sorted(variables.items()):
            check(ctx, user, name, v)
            conf.append("%s=%s" % (name, v))
            sh.append("export %s=%s" % (name, sh_quote(v)))
        ctx.file(
            "~/.config/environment.d/60-wrath.conf",
            lines(conf),
            user = user,
            next_login = True,
        )
        ctx.file(
            "~/.config/wrath/session.sh",
            lines(sh),
            user = user,
            next_login = True,
        )
        # fish reads no POSIX shell, so it gets the same variables its own way. Nushell's are in
        # its config, which its module writes.
        if u.get("shell") == "fish":
            ctx.file(
                "~/.config/fish/conf.d/wrath.fish",
                lines([fish_line(name, v) for name, v in sorted(variables.items())]),
                user = user,
                next_login = True,
            )

module(
    name = "session",
    options = {},
    user_options = {
        "environment": option(
            types.map(types.str),
            doc = "Variables every session of the user has. Values may refer to others as `$NAME`.",
        ),
    },
    render = render,
    configurations = ["system", "home"],
)
