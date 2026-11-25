# The default PAM stacks for local logins and sudo, and `other`, which refuses services that have
# none of their own.

load("lib/pam.star", "unix_stacks")

DENY = [{"name": "deny", "control": "required", "module": "pam_deny.so"}]

def render(ctx: Context) -> None:
    for service in ["login", "sudo"]:
        ctx.set("security.pam.services." + service, unix_stacks())
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
