# Programs as their projects build them for other distributions, such as browsers, which take an
# hour or more and their own toolchains to compile. The build is copied whole into a directory of
# its own and its programs pointed at our loader and libraries.
#
# Only programs are changed. Each gets our loader, and its own directory and the recipe's
# dependencies' libraries as an old-style run path (DT_RPATH), which the loader also uses for the
# libraries the program loads, and those load, when they have no run path of their own. Libraries
# are left as built: Mozilla's pack their relocations with code of their own that breaks when a
# tool moves their sections.

PATCH = """loader=$WRATH_LOADER
rpath='$ORIGIN':$(printf '%s\\n' $WRATH_LINK_FLAGS | sed -n 's/^-Wl,-rpath,//p' | paste -sd: -)
find "$app" -type f | while read -r file; do
    [ "$(head -c 4 "$file" | od -An -c | tr -d ' ')" = '177ELF' ] || continue
    readelf -l "$file" | grep -q 'program interpreter' || continue
    chmod u+w "$file"
    patchelf --set-interpreter "$loader" --force-rpath --set-rpath "$rpath" "$file"
done
"""

# Programs built elsewhere bind every function as they start, so a library or function missing
# here is a program that won't start on the machine. The loader resolves each program and
# library, as `ldd -r` does, with the build's directory and the run path the programs give the
# libraries they load.
CHECK = """missing=$(find "$app" -type f \\( -name '*.so' -o -name '*.so.*' -o -perm -u+x \\) |
  sort | while read -r file; do
    [ "$(head -c 4 "$file" | od -An -c | tr -d ' ')" = '177ELF' ] || continue
    LD_LIBRARY_PATH="$app:$(dirname "$file"):$rpath" LD_TRACE_LOADED_OBJECTS=1 LD_WARN=yes \\
      LD_BIND_NOW=yes "$loader" "$file" 2>&1 | grep -E 'not found|undefined symbol' |
      sed "s#^#${file#$app/}: #" || true
  done)
if [ -n "$missing" ]; then
  echo "programs here would fail to start, missing:" >&2
  printf '%s\\n' "$missing" >&2
  exit 1
fi
"""

def build(recipe: Recipe, options: dict[str, typing.Any]) -> dict[str, typing.Any]:
    lib = options["dir"] or recipe.id
    lines = ["app=$DEST$PREFIX/lib/" + lib, "mkdir -p $app $DEST$PREFIX/bin", "cp -r . $app/"]
    lines += ["rm -rf $app/" + path for path in options["remove"]]
    script = "".join([line + "\n" for line in lines]) + PATCH + CHECK
    exports = "".join(["export %s=%s\n" % item for item in sorted(options["env"].items())])
    for name, path in sorted(options["programs"].items()):
        bin = "$DEST$PREFIX/bin/" + name
        if exports:
            script += "printf '#!/bin/sh\\n%sexec %%s \"$@\"\\n' \"$PREFIX/lib/%s/%s\" > %s\n" % (
                exports.replace("\n", "\\n"),
                lib,
                path,
                bin,
            )
            script += "chmod +x %s\n" % bin
        else:
            script += "ln -s ../lib/%s/%s %s\n" % (lib, path, bin)
    return {"script": script + options["install"], "deps": ["patchelf"]}

style(
    name = "prebuilt",
    options = {
        "dir": option(
            types.str,
            default = "",
            doc = "The directory under `lib` the build goes in; the recipe's id when empty.",
        ),
        "programs": option(
            types.map(types.str),
            default = {},
            doc = "Commands to put in `bin`, each the path of its program in the build, such " +
                  "as `{ zen = \"zen\" }`.",
        ),
        "env": option(
            types.map(types.str),
            default = {},
            doc = "Variables each command starts its program with, which makes the commands " +
                  "small scripts instead of links.",
        ),
        "remove": option(
            types.list(types.str),
            default = [],
            doc = "Paths in the build to leave out, such as its own updater.",
        ),
        "install": option(
            types.str,
            default = "",
            doc = "Shell lines run after, with `$app` the build's directory: desktop files, " +
                  "icons and policies.",
        ),
    },
    build = build,
)
