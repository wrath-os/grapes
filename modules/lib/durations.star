# Helpers modules load with `load("lib/durations.star", "seconds")`.

UNITS = [("min", 60), ("sec", 1), ("s", 1), ("m", 60), ("h", 3600)]

def seconds(ctx: Context, path: str, text: str) -> int:
    """The seconds in a time such as `90s`, `15min` or `1h`, as systemd writes them; an error at
    `path` otherwise."""
    for suffix, scale in UNITS:
        number = text[:-len(suffix)]
        if text.endswith(suffix) and number.isdigit():
            return int(number) * scale
    if text.isdigit():
        return int(text)
    ctx.error(path, "a time such as `90s`, `15min` or `1h`")
    return 0
