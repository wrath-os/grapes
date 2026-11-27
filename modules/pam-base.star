# The default PAM stacks for local logins and sudo, and `other`, which refuses services that have
# none of their own.

load("lib/pam.star", "unix_stacks")

DENY = [{"name": "deny", "control": "required", "module": "pam_deny.so"}]

# What wrath has to say about the machine as people log in, such as an automatic upgrade that
# failed or a generation that didn't boot: a file per subject, there only while it applies.
NOTICES = "/wrath/system/notice.d"

def render(ctx: Context) -> None:
    for service in ["login", "sudo"]:
        ctx.set("security.pam.services." + service, unix_stacks())
    logins = ["login"] + (["sshd"] if ctx.read("services.ssh.enable") else [])
    for service in logins:
        ctx.set("security.pam.services.%s.session" % service, [
            {
                "name": "notice",
                "control": "optional",
                "module": "pam_motd.so",
                "args": ["motd_dir=" + NOTICES],
                "after": "systemd",
            },
        ])
    ctx.set("security.pam.services.other", {
        "account": DENY,
        "auth": DENY,
        "password": DENY,
        "session": DENY,
    })

module(
    name = "pam-base",
    options = {},
    render = render,
)
