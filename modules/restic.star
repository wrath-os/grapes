# Backups with restic on a timer: each one copies its paths to a repository, such as a bucket,
# encrypted with its password.

load("lib/service.star", "systemd_arg")

def render(ctx: Context) -> None:
    backups = ctx.read("services.restic.backups")
    if not backups:
        return
    ctx.package("restic")
    for name, backup in backups.items():
        if not backup["paths"]:
            ctx.error(
                "services.restic.backups.%s.paths" % name,
                "a backup of nothing: list the paths it copies",
            )
        unit = "restic-backup-" + name
        excludes = ["--exclude=" + pattern for pattern in backup["exclude"]]
        args = ["restic", "backup"] + excludes + backup["paths"]
        service = {
            "Type": "oneshot",
            "User": backup["user"],
            "Environment": [
                "RESTIC_REPOSITORY=" + backup["repository"],
                "RESTIC_PASSWORD_FILE=" + backup["password"],
                # Its cache grows to gigabytes, so it's kept where caches are, not in a home.
                "RESTIC_CACHE_DIR=%C/" + unit,
            ],
            "CacheDirectory": unit,
            "ExecStart": " ".join([systemd_arg(arg) for arg in args]),
            # A backup reads everything but shouldn't slow down whoever's using the machine.
            "Nice": 19,
            "IOSchedulingClass": "idle",
        }
        if "environment" in backup:
            service["EnvironmentFile"] = backup["environment"]
        if backup["initialize"]:
            # restic says 10 when there's no repository there yet.
            service["ExecStartPre"] = (
                "/bin/sh -c 'restic cat config >/dev/null 2>&1; [ $? -ne 10 ] || restic init'"
            )
        ctx.unit(unit + ".service", {
            "Unit": {
                "Description": "Back up to " + backup["repository"],
                "Wants": ["network-online.target"],
                "After": ["network-online.target"],
            },
            "Service": service,
        })
        ctx.unit(unit + ".timer", {
            "Unit": {"Description": "Back up to %s %s" % (backup["repository"], backup["when"])},
            "Timer": {
                "OnCalendar": backup["when"],
                "RandomizedDelaySec": "5m",
                # A machine that was off at the time backs up when it's back.
                "Persistent": True,
            },
            "Install": {"WantedBy": ["timers.target"]},
        })

backup = types.record(
    repository = option(
        types.str,
        required = True,
        doc = "Where backups go, as restic names it, such as " +
              "`s3:https://hel1.your-objectstorage.com/bucket` or `/mnt/backup`.",
    ),
    password = option(
        types.path,
        required = True,
        runtime = True,
        doc = "A file with the repository's password, usually a secret: " +
              "`{ secret = \"restic-password\" }`.",
    ),
    environment = option(
        types.path,
        optional = True,
        runtime = True,
        doc = "A file of `NAME=value` lines for restic, such as the bucket's " +
              "`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, usually a secret.",
    ),
    paths = option(types.set(types.str), doc = "What it copies."),
    exclude = option(
        types.set(types.str),
        doc = "Patterns for what it leaves out, as restic's `--exclude` takes them, such as " +
              "`node_modules` or `*/target`.",
    ),
    when = option(
        types.str,
        default = "hourly",
        doc = "When it runs, as a systemd calendar time.",
    ),
    user = option(
        types.str,
        default = "root",
        doc = "Who it runs as, who has to be able to read every path.",
    ),
    initialize = option(
        types.bool,
        default = True,
        doc = "Whether the first backup makes the repository when there's none there yet.",
    ),
)

module(
    name = "restic",
    options = {"services.restic.backups": types.map(backup)},
    render = render,
    configurations = ["system"],
)
