# go.star

Build and test targets for a Go module, derived from `go list` - mains are
found by package name, so `cmd/<name>/`, a root `main.go`, or any other
layout all work unmodified.

## The floor

```yaml
# giant.yaml
workspace: { name: example }
std: { ref: v1 }
generate:
  - { script: gen.star, infix: go }
```

```python
# gen.star
load("@std//go.star", "go_targets")

def generate(ws):
    go_targets(ws)
```

`giant gen` then writes one `giant.go.yaml` per package. For a module with
`cmd/api/` and a tested `internal/store/`:

```yaml
# cmd/api/giant.go.yaml
targets:
- name: api
  inputs:
  - //cmd/api/*.go
  - //go.mod
  - //go.sum
  outputs:
  - //bin/api
  command: go build -o $GIANT_WORKSPACE_ROOT/bin/api .
  tags: [kind=bin, lang=go]
```

```yaml
# internal/store/giant.go.yaml
targets:
- name: test
  inputs: [...]
  outputs: [//output/test/internal_store.ok]
  command: go test ./... && mkdir -p $GIANT_WORKSPACE_ROOT/output/test && touch ...
  test: true
  cache: false
  tags: [kind=test, lang=go]
```

Inputs are derived per package: its own `*.go`, every first-party transitive
dep's `*.go`, `go:embed` files, and `go.mod`/`go.sum` - so a change in a
shared package rebuilds exactly its dependents.

`go_targets(ws, dir, deps, test_deps, output)`: `dir` is the module dir for
a module that doesn't sit at the workspace root; `deps` ride every target
(e.g. a toolchain-identity target); `output` templates the install path
(`"bin/{name}"`).

## The pieces

When the floor doesn't fit, compose the same parts it is built from:

| Function | What it does |
|---|---|
| `go_list(ws, dir)` | Raw `go list -json -deps ./...`. Run once, feed the others. |
| `packages_of(ws, raw)` | First-party packages: dir, name, is_main, deps, embeds, has_tests. |
| `go_index(pkgs)` | Import path -> package, for input derivation. |
| `go_inputs(pkg, index, mod_dir)` | The derived input globs for one package. |
| `bin_name(dir)` | Binary name from a package dir (`foo/cmd` -> `foo`). |
| `go_binary(name, pkg, inputs, output, ...)` | Emit one build target. |
| `go_test(pkg, inputs, ...)` | Emit one test target. |
| `cgo_index_of(raw)` | Import path -> cgo link libs, from `#cgo LDFLAGS`. |
| `cgo_libs_for(p, cgo_index)` | The libs a main pulls in transitively ([] = pure Go). |

## Cross builds and cgo

`go_binary(goos = ..., goarch = ...)` emits a `CGO_ENABLED=0` cross build.
Its `env` parameter overlays those defaults, which is the hook for a cgo
floor: detect cgo mains with the index, then reuse the emitter with your
repo's compiler and flags.

```python
load("@std//go.star", "go_list", "packages_of", "go_index", "go_inputs",
     "go_binary", "bin_name", "cgo_index_of", "cgo_libs_for")

def generate(ws):
    raw = go_list(ws)
    pkgs = packages_of(ws, raw)
    index = go_index(pkgs)
    cgo = cgo_index_of(raw)
    for p in pkgs:
        if not p["is_main"]:
            continue
        name = bin_name(p["dir"])
        libs = cgo_libs_for(p, cgo)
        for (os, arch) in [("linux", "amd64"), ("linux", "arm64")]:
            env = {}
            if libs:
                env = {
                    "CGO_ENABLED": "1",
                    "CC": "zig cc -target " + arch + "-linux-gnu",
                    "CGO_LDFLAGS": "-L/your/sysroot/" + arch + "/lib",
                }
            go_binary(
                name + "-" + os + "-" + arch, p, go_inputs(p, index),
                "out/" + os + "-" + arch + "/bin/" + name,
                goos = os, goarch = arch, env = env,
                extra_tags = ["lib=" + l for l in libs],
            )
```

Where the sysroot lives and which compiler crosses it is your repo's
infrastructure; the library's job ends at detecting the cgo mains and
shaping the target.
