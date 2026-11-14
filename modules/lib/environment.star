# A user's environment, written for shells that don't read POSIX shell: values are text with
# references to other variables as `$NAME` or `${NAME}`, which each shell writes its own way.

def parts(value: str) -> list[tuple[str, ...]]:
    """`value` as text and references, in order: `("text", ...)` and `("name", ...)`."""
    out = []
    text = ""
    i = 0
    for _ in range(len(value) + 1):
        if i >= len(value):
            break
        c = value[i]
        if c != "$" or i + 1 >= len(value):
            text += c
            i += 1
            continue
        braced = value[i + 1] == "{"
        start = i + 2 if braced else i + 1
        end = start
        for _ in range(len(value)):
            if end < len(value) and (value[end].isalnum() or value[end] == "_"):
                end += 1
            else:
                break
        if end == start or (braced and (end >= len(value) or value[end] != "}")):
            text += c
            i += 1
            continue
        if text:
            out.append(("text", text))
            text = ""
        out.append(("name", value[start:end]))
        i = end + 1 if braced else end
    if text:
        out.append(("text", text))
    return out

def nu_line(name: str, value: str) -> str:
    """`$env.NAME = ...` for Nushell, with references as `($env.OTHER)`."""
    pieces = []
    for kind, piece in parts(value):
        if kind == "name":
            pieces.append("($env.%s)" % piece)
        else:
            for c in ["\\", "\"", "(", ")"]:
                piece = piece.replace(c, "\\" + c)
            pieces.append(piece)
    return "$env.%s = $\"%s\"" % (name, "".join(pieces))

def fish_line(name: str, value: str) -> str:
    """`set -gx NAME ...` for fish, with references as `"$OTHER"`."""
    pieces = []
    for kind, piece in parts(value):
        if kind == "name":
            # Out of the quotes for a moment, which ends the name whatever follows it.
            pieces.append("\"$%s\"" % piece)
        else:
            for c in ["\\", "\"", "$"]:
                piece = piece.replace(c, "\\" + c)
            pieces.append(piece)
    return "set -gx %s \"%s\"" % (name, "".join(pieces))
