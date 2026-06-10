Giant's Starlark standard library: generator modules that
[`giant gen`](https://giant.build/guides/generating-config/) loads as
`@std//<name>`.

## Use

Pin a release in your workspace's root `giant.yaml`:

```yaml
std:
  ref: v1            # a tag or commit sha of this repo
```

then load modules from your `giant.star`:

```python
load("@std//cargo.star", "cargo_targets")

def generate(ws):
    cargo_targets(ws)
```

Modules are fetched once per pin and cached locally, so generation runs
offline after the first fetch. A checkout of this repo works without the
network at all (`std: { path: ../giant-std }`), and
`giant gen vendor <name>` copies a module into your repo for editing.

## Modules

| Module | What it generates | Docs |
|---|---|---|
| `cargo.star` | A release build+install target per Rust workspace binary, from `cargo metadata`. | [docs/cargo.md](docs/cargo.md) |
| `go.star` | Build and test targets per Go package, from `go list` (cgo-aware). | [docs/go.md](docs/go.md) |
| `docker.star` | Image targets: shared-template or co-located Dockerfiles. | [docs/docker.md](docs/docker.md) |
| `controllergen.star` | kubebuilder deepcopy/conversion + CRD targets, from marker files. | [docs/controllergen.md](docs/controllergen.md) |

Modules are plain Starlark over giant's generic host primitives
(`ws.exec`, `ws.glob`, `parse_json`, `target()`) - read them, vendor them,
or use them as a starting point for your own. Each is layered the same way:
**detectors** that derive facts from the tree, **emitters** that shape one
correct target, and a **floor** that wires them into the common convention.
When the floor doesn't fit your repo, call the same detectors and emitters
from your own `giant.star` - extension is recomposition, and the floors are
each a screenful of Starlark to crib from. Workspace-specific knobs belong
in a top-level block of your root `giant.yaml`
([docs/workspace-config.md](docs/workspace-config.md)).

## Versioning

Tags (`v1`, `v2`, ...) are the pin points. A tag never moves once
published; pin a commit sha if you want immutability guaranteed by
content rather than convention.

## License

Apache-2.0. See [LICENSE](LICENSE).
