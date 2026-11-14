# Projects built with CMake and Ninja, configured with the `-D` options a recipe gives.

def exports(options: dict[str, typing.Any]) -> list[str]:
    """The build's variables, and its compiler flags in double quotes, so variables in them still
    expand, added to what the build has."""
    lines = ["export %s=%s" % item for item in options["env"].items()]
    for name, key in [("CFLAGS", "cflags"), ("CXXFLAGS", "cxxflags")]:
        if options[key]:
            if name in options["env"]:
                fail("`%s` and `env.%s` both set %s; say it once" % (key, name, name))
            flags = " ".join([] + options[key])
            for special in ["\\", "\"", "`"]:
                flags = flags.replace(special, "\\" + special)
            lines.append("export %s=\"%s\"" % (name, flags))
    return lines

def ended(text: str) -> str:
    """`text`, ending its last line, so what follows starts on a line of its own."""
    return text if text == "" or text.endswith("\n") else text + "\n"

def build(recipe: Recipe, options: dict[str, typing.Any]) -> dict[str, typing.Any]:
    configure = (
        "cmake -S %s -B /build/b -G Ninja -DCMAKE_INSTALL_PREFIX=$PREFIX " +
        "-DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release"
    ) % options["source"]
    lines = exports(options) + [
        " ".join([configure] + options["args"]),
        "ninja -C /build/b -j$NPROC",
        "DESTDIR=$DEST ninja -C /build/b install",
    ]
    return {
        "script": ended(options["prepare"]) + "".join([line + "\n" for line in lines]) +
                  options["install"],
        "deps": ["cmake", "ninja", "pkgconf"],
    }

style(
    name = "cmake",
    files = ["CMakeLists.txt"],
    options = {
        "args": option(
            types.list(types.str),
            doc = "Arguments for `cmake`, such as `-DBUILD_TESTING=OFF`.",
        ),
        "source": option(types.str, default = ".", doc = "The directory with `CMakeLists.txt`."),
        "env": option(types.map(types.str), doc = "Variables the build has."),
        "cflags": option(
            types.list(types.str),
            default = [],
            doc = "Flags for the C compiler, such as `-std=gnu17` for old C, quoted for the shell.",
        ),
        "cxxflags": option(
            types.list(types.str),
            default = [],
            doc = "Flags for the C++ compiler, quoted for the shell.",
        ),
        "prepare": option(types.str, default = "", doc = "Shell lines run before configuring."),
        "install": option(
            types.str,
            default = "",
            doc = "Shell lines run after the install, for what it leaves out.",
        ),
    },
    build = build,
)
