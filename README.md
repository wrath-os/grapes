The packages and modules [wrath](https://github.com/wrath-os/wrath) systems are made of: a
recipe for every package, the build styles recipes use, and the Starlark modules that turn a
configuration into a system.

```toml
# your system.toml: packages from grapes, and its modules, without naming either
packages = ["ripgrep", "ghostty"]

[services.ssh]
enable = true
```

A configuration pins grapes in its lock like any source, so `wrath update grapes` moves it
forward and a rollback takes it back with the rest of the system.

## Working on it

Build a package from a checkout, or point a configuration at one:

```sh
wrath build ripgrep --check
wrath -C ~/machines/laptop plan --source grapes=.
```

- `recipes/`: one entry per package; see [docs/recipes.md](docs/recipes.md).
- `styles/`: how recipes build, such as meson, cargo or zig.
- `modules/`: the modules, with their tests in `modules/tests`; `wrath dev test modules/tests`.
- `seed.pin` and `sources.lock`: what the toolchain starts from, and every source's hash.
- [docs/reference/options.md](docs/reference/options.md): every option the modules declare,
  written by `wrath dev docs`.
- [docs/packaging-findings.md](docs/packaging-findings.md): what went wrong packaging, and what
  would prevent it.
