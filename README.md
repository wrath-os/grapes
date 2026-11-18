Everything a [wrath](https://github.com/wrath-os/wrath) system is made of: a recipe for every
package, the build styles those recipes use, and the Starlark modules that turn a configuration
into a running system.

```toml
# your system.toml: packages from grapes, and its modules, without naming either
packages = ["ripgrep", "ghostty"]

[services.ssh]
enable = true
```

You don't have to install grapes or point at it. A configuration pins it in its lock like any
other source, so `wrath update grapes` moves you forward and `wrath rollback` takes you back,
packages and modules along with the rest of the system.

## What's in here

- About 370 packages: a niri desktop, development tools, servers and the usual command line
  things. Each recipe is a short TOML file with its sources pinned in a lock next to it, and
  everything builds from source in wrath's sandbox.
- Around 50 modules for users, services, disks, networking, audio, the desktop and more, each
  with its own tests. Every option they declare is listed in
  [docs/reference/options.md](docs/reference/options.md).
- A seed, the small toolchain everything else is built from.

## Working on it

Clone it next to wrath and build a package from your checkout, or point a configuration at it:

```sh
wrath --source grapes=. build ripgrep --check
wrath -C ~/machines/laptop plan --source grapes=.
```

- `recipes/`: a file per package or family, such as `recipes/jq/jq.toml`; see
  [recipes and styles](https://github.com/wrath-os/wrath/blob/main/docs/recipes.md).
- `styles/`: how recipes build, such as meson, cargo or zig.
- `modules/`: the modules, with their tests in `modules/tests`; run them with
  `wrath dev test modules/tests`.
- `seed.pin`: what the toolchain starts from.
- [docs/packaging-findings.md](docs/packaging-findings.md): what went wrong while packaging, and
  what would stop it happening again.

Adding a package is usually one small file. If something you want is missing, a recipe is the
best place to start.
