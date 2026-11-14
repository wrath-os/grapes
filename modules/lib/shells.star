# The login shells a user can name, each with its package and program.

SHELLS = {
    "bash": {"package": "bash", "program": "bash"},
    "zsh": {"package": "zsh", "program": "zsh"},
    "fish": {"package": "fish", "program": "fish"},
    "nushell": {"package": "nushell", "program": "nu"},
}

def shell_path(shell: str) -> str | None:
    """The program a login shell runs: the named shell's, a path as it's given, or `None` for a
    name that isn't a shell."""
    if shell.startswith("/"):
        return shell
    if shell in SHELLS:
        return "/run/system/bin/" + SHELLS[shell]["program"]
    return None
