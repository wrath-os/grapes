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
forward and a rollback takes it back with the rest of the system. It isn't published yet, so for
now clone it beside [wrath](https://github.com/wrath-os/wrath) and give wrath the checkout with
`--source grapes=../grapes` or `WRATH_GRAPES`.

## Working on it

Build a package from a checkout, or point a configuration at one:

```sh
wrath build ripgrep --check
wrath -C ~/machines/laptop plan --source grapes=.
```

- `recipes/`: a file per package or family, such as `recipes/jq/jq.toml`, with the lock pinning
  its sources beside it; see
  [recipes and styles](https://github.com/wrath-os/wrath/blob/main/docs/recipes.md).
- `styles/`: how recipes build, such as meson, cargo or zig.
- `modules/`: the modules, with their tests in `modules/tests`; `wrath dev test modules/tests`.
- `seed.pin`: what the toolchain starts from.
- [docs/reference/options.md](docs/reference/options.md): every option the modules declare,
  written by `wrath dev docs`.
- [docs/packaging-findings.md](docs/packaging-findings.md): what went wrong packaging, and what
  would prevent it.
