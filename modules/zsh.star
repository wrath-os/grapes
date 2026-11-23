# zsh for each user who has it as their login shell or enables it: `~/.zshrc`, with history,
# completion, options, aliases and lines of their own. A login zsh reads /etc/profile, as a login
# bash does, so it has the system's PATH and the user's environment.

def quoted(text: str) -> str:
    """`text` in single quotes, for zsh."""
    return "'" + text.replace("'", "'\\''") + "'"

def zshrc(zsh: dict[str, typing.Any]) -> str:
    lines = [
        "# Written by wrath from the configuration; changes here are replaced.",
        "HISTFILE=$HOME/.zsh_history",
        "HISTSIZE=%d" % zsh["history"],
        "SAVEHIST=%d" % zsh["history"],
    ]
    if zsh["completion"]:
        lines.append("autoload -Uz compinit && compinit")
    lines += ["setopt " + option for option in zsh["options"]]
    aliases = sorted(zsh["aliases"].items())
    lines += ["alias %s=%s" % (name, quoted(value)) for name, value in aliases]
    text = "".join([line + "\n" for line in lines])
    return text + zsh["init"] if zsh["init"] else text

def render(ctx: Context) -> None:
    anyone = False
    for user, u in ctx.read("users").items():
        zsh = u["programs"]["zsh"]
        if not (zsh["enable"] or u.get("shell") == "zsh"):
            continue
        anyone = True
        ctx.file("~/.zshrc", zshrc(zsh), user = user)
        ctx.package("zsh", user = user)
    if anyone:
        ctx.file("/etc/zprofile", "emulate sh -c '. /etc/profile'\n", 0o644, next_login = True)

module(
    name = "zsh",
    options = {},
    user_options = {
        "programs.zsh": types.record(
            enable = option(
                types.bool,
                default = False,
                doc = "zsh with these settings for a user whose login shell is another.",
            ),
            history = option(types.int, default = 10000, doc = "How many commands it keeps."),
            completion = option(types.bool, default = True, doc = "zsh's own completion."),
            options = option(
                types.list(types.str),
                default = [],
                doc = "zsh options to turn on, such as `share_history`.",
            ),
            aliases = option(
                types.map(types.str),
                default = {},
                doc = "Aliases by name, such as `{ ll = \"ls -l\" }`.",
            ),
            init = option(
                types.str,
                default = "",
                doc = "Lines run after the rest, in every interactive zsh.",
            ),
        ),
    },
    render = render,
    configurations = ["system"],
)
