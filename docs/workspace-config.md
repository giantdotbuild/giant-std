# Workspace config for generators

Giant's root `giant.yaml` is open at the top level: the engine validates the
sections it owns (`workspace`, `cache`, `remote`, `state`) and ignores keys
it doesn't recognise. That makes the root file a natural home for your
generator's configuration - one declarative block, no sidecar files - which
your `giant.star` reads back with `ws.read` + `parse_yaml`.

```yaml
# giant.yaml
workspace:
  name: example

std:
  ref: v1

generate:
  - { script: gen.star, infix: gen }

# Your own block. The engine ignores it; your generator owns it.
images:
  registry: registry.example.com/platform
  exclude: [load-tester]
  names:
    cmd/api-server: api
```

```python
# gen.star
load("@std//go.star", "go_packages", "bin_name")
load("@std//docker.star", "docker_image")

def generate(ws):
    cfg = parse_yaml(ws.read("giant.yaml")).get("images", {})
    registry = cfg.get("registry", "registry.local")
    exclude = {x: True for x in cfg.get("exclude", [])}
    names = cfg.get("names", {})

    for p in go_packages(ws):
        if not p["is_main"]:
            continue
        name = names.get(p["dir"], bin_name(p["dir"]))
        if name in exclude:
            continue
        docker_image(
            name = "image",
            image = registry + "/" + name,
            context = "out",
            dockerfile = "build/Dockerfile",
            args = {"OUTPUT_NAME": name},
            inputs = ["//out/bin/" + name],
            package = p["dir"],
        )
```

Conventions that have worked well:

- One block per generator concern, named for what it configures (`images:`,
  `codegen:`), with every field defaulted in the generator so an absent
  block means "the convention, unmodified".
- Keys that *override* the convention (a curated image name, an exclusion)
  rather than keys that restate what the tree already says.
- Validate early: `fail("images.registry must be set")` from the generator
  beats a broken target at build time.

The same parsers handle other sources too: `parse_json`, `parse_toml`, and
`parse_json_stream` (for concatenated objects, like `go list -json` output)
all return plain Starlark data.
