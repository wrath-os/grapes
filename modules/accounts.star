# Changing who you are: sudo for the `wheel` group, su, and
# passwd, which run as root through wrappers, runuser, and the PAM stacks they use.

load("lib/home.star", "home_of")
load("lib/pam.star", "unix_stacks")
load("lib/shells.star", "SHELLS", "shell_path")

SW = "/run/system/bin/"

# Groups every system has, at the numbers they always have.
FIXED_GROUPS = {"root": 0, "wheel": 10, "users": 100, "nogroup": 65534}

def allocate(
        ctx: Context,
        kind: str,
        wanted: dict[str, typing.Any],
        locked: dict[str, int],
        ids: range) -> dict[str, int]:
    """Each name in `wanted` its own id when it's set, else the one the lock keeps, else the
    first in `ids` nobody has. A name the lock keeps but nothing wants any more keeps its id, so
    a new name never gets a removed one's files. Gives what the lock keeps from now on."""
    kept = dict(locked)
    holders = {id: name for name, id in locked.items()}
    for name in sorted(wanted):
        id = wanted[name]
        if id == None:
            continue
        if holders.get(id, name) != name:
            ctx.error(
                ["users", name, kind],
                "%s %d is kept for `%s` in the lock" % (kind, id, holders[id]),
            )
        kept[name] = id
        holders[id] = name
    for name in sorted(wanted):
        if name in kept:
            continue
        for id in ids:
            if id not in holders:
                kept[name] = id
                holders[id] = name
                break
    return kept

def is_password_hash(text: str) -> bool:
    """Whether `text` is a crypt hash such as `$6$salt$hash`, or `!` or `*`, which allow no
    password. A placeholder such as `$6$...` is neither, and would lock the user out."""
    if text in ["!", "*"]:
        return True
    parts = text.split("$")
    return len(parts) >= 4 and parts[0] == "" and "" not in parts[1:] and "..." not in text

def account_files(
        ctx: Context,
        users: dict[str, typing.Any],
        locked: dict[str, typing.Any]) -> dict[str, typing.Any]:
    """/etc/passwd, /etc/group and /etc/shadow for root, nobody and `users`, with the uids and
    gids the lock keeps from then on. Users get uids from 1000, system users from 999 down, and
    groups from 400; a user's own `uid` wins. A password set on the machine is kept by
    activation."""
    uids = allocate(
        ctx,
        "uid",
        {name: u.get("uid") for name, u in users.items() if not u["system"]},
        locked["users"],
        range(1000, 60000),
    )
    uids = allocate(
        ctx,
        "uid",
        {name: u.get("uid") for name, u in users.items() if u["system"]},
        uids,
        range(999, 0, -1),
    )
    members = {}
    for name in sorted(users):
        for group in users[name]["extra_groups"]:
            members[group] = members.get(group, []) + [name]
    own_groups = {
        group: None
        for group in list(members) + [u["group"] for u in users.values()]
        if group not in FIXED_GROUPS
    }
    gids = allocate(ctx, "gid", own_groups, locked["groups"], range(400, 1000))
    gid = FIXED_GROUPS | gids

    passwd = ["root:x:0:0:root:/root:/bin/sh", "nobody:x:65534:65534:nobody:/:/bin/sh"]
    shadow = ["root:*:1::::::", "nobody:*:1::::::"]
    shells = {"/bin/sh": None, SW + "sh": None, SW + "bash": None}
    for name in sorted(users):
        u = users[name]
        shell = shell_path(u.get("shell", "bash"))
        if shell == None:
            ctx.error(
                ["users", name, "shell"],
                "a login shell is one of %s, or a path" % ", ".join(sorted(SHELLS)),
            )
            shell = SW + "bash"
        shells[shell] = None
        if not is_password_hash(u.get("initial_hashed_password", "!")):
            ctx.error(
                ["users", name, "initial_hashed_password"],
                "this isn't a password hash, which `mkpasswd -m sha-512` makes, or `!` for none",
            )
        for field in ["description", "home", "shell"]:
            if any([c in str(u.get(field, "")) for c in [":", "\n"]]):
                ctx.error(
                    ["users", name, field],
                    "a `:` or line break would end the field in /etc/passwd",
                )
        passwd.append("%s:x:%d:%d:%s:%s:%s" % (
            name,
            uids[name],
            gid[u["group"]],
            u.get("description", ""),
            home_of(name, u),
            shell,
        ))
        shadow.append("%s:%s:1::::::" % (name, u.get("initial_hashed_password", "!")))
    group = [
        "root:x:0:",
        "wheel:x:10:" + ",".join(members.get("wheel", [])),
        "nogroup:x:65534:",
        "users:x:100:" + ",".join(members.get("users", [])),
    ]
    for name in sorted(own_groups):
        group.append("%s:x:%d:%s" % (name, gid[name], ",".join(members.get(name, []))))
    return {
        "passwd": lines(passwd),
        "group": lines(group),
        "shells": lines(list(shells)),
        "shadow": lines(shadow),
        "ids": {"users": uids, "groups": gids},
    }

def render(ctx: Context) -> None:
    for package in ["sudo", "linux-pam", "shadow"]:
        ctx.package(package)
    accounts = account_files(ctx, ctx.read("users"), ctx.locked_ids())
    ctx.base("ids", accounts["ids"])
    ctx.file("/etc/passwd", accounts["passwd"], 0o644)
    ctx.file("/etc/group", accounts["group"], 0o644)
    ctx.file("/etc/shadow", accounts["shadow"], 0o600)
    # The login shells there are, which chsh and some session scripts check.
    ctx.file("/etc/shells", accounts["shells"], 0o644)
    for u in ctx.read("users").values():
        if u.get("shell") in SHELLS:
            ctx.package(SHELLS[u["shell"]]["package"])
    # unix_chkpwd lets PAM check a password for someone who isn't root.
    for name in ["sudo", "su", "passwd", "unix_chkpwd"]:
        ctx.wrapper(name, source = SW + name)
    ctx.file(
        "/etc/sudoers",
        "root ALL=(ALL:ALL) SETENV: ALL\n%wheel ALL=(ALL:ALL) SETENV: ALL\n",
        0o440,
    )

    su = unix_stacks()
    su["auth"] = [{"name": "rootok", "control": "sufficient", "module": "pam_rootok.so"}] + [
        dict(rule, after = "rootok") if rule["name"] == "env" else rule
        for rule in su["auth"]
    ]
    ctx.set("security.pam.services.su", su)
    ctx.set("security.pam.services.passwd", unix_stacks())
    # systemd starts each user's own service manager through this one.
    ctx.set("security.pam.services.systemd-user", unix_stacks())
    # root running something as another user, which needs no password.
    runuser = {
        "auth": [{"name": "rootok", "control": "sufficient", "module": "pam_rootok.so"}],
        "account": [{"name": "unix", "control": "required", "module": "pam_unix.so"}],
        "session": [{"name": "unix", "control": "required", "module": "pam_unix.so"}],
    }
    ctx.set("security.pam.services.runuser", runuser)
    ctx.set("security.pam.services.runuser-l", runuser)

module(
    name = "accounts",
    options = {},
    render = render,
)
