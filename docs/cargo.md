# cargo.star

A release build-and-install target per Rust workspace binary, derived from
`cargo metadata`.

## The floor

```yaml
# giant.yaml
workspace: { name: example }
std: { ref: v1 }
generate:
  - { script: gen.star, infix: rust }
```

```python
# gen.star
load("@std//cargo.star", "cargo_targets")

def generate(ws):
    cargo_targets(ws, exclude = ["examples-fixture"])
```

For a workspace with `crates/server/`, `giant gen` writes:

```yaml
# crates/server/giant.rust.yaml
targets:
- name: server
  inputs:
  - src/**/*.rs
  - Cargo.toml
  - //Cargo.toml
  - //Cargo.lock
  outputs:
  - //bin/server
  command: cargo build --release -p server --bin server && install -m 0755
    target/release/server $GIANT_WORKSPACE_ROOT/bin/server
  cwd: //
  timeout_secs: 600
  tags: [bin, rust]
```

Inputs are package-relative (`src/**/*.rs`, the crate manifest, `build.rs`
when present) plus the workspace manifest and lockfile, so a dependency bump
rebuilds every binary while a single crate's edit rebuilds only its own.

`cargo_targets(ws, deps, dir, exclude)`: `deps` ride every target; `dir`
points at a workspace that doesn't sit at the repo root; `exclude` skips
members by crate name (example crates a workspace lists but doesn't ship).

## The pieces

| Function | What it does |
|---|---|
| `cargo_metadata(ws, dir)` | Raw `cargo metadata --no-deps`. |
| `cargo_packages(ws, meta)` | Member packages: name, dir, bin target names. |
| `cargo_inputs(ws, pkg, dir, extra)` | The input globs for one crate. |
| `cargo_bin(ws, pkg, bin, ...)` | Emit one build-and-install target. |

A binary that needs more than the floor offers - cargo features, non-Rust
compile-time inputs (query files, templates, included assets) - drops down
one level: exclude its crate from the floor and emit it directly.

```python
load("@std//cargo.star", "cargo_targets", "cargo_metadata", "cargo_packages", "cargo_bin")

def generate(ws):
    cargo_targets(ws, exclude = ["server"])
    for pkg in cargo_packages(ws, cargo_metadata(ws)):
        if pkg["name"] == "server":
            cargo_bin(
                ws, pkg, "server",
                features = ["postgres"],
                extra_inputs = ["queries/**/*.sql"],
            )
```
