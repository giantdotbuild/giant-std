# controllergen.star

kubebuilder codegen targets (controller-gen, conversion-gen), detected from
the marker files the ecosystem already leaves in the tree - no sidecar
config, and a new API type or group is picked up by the next `giant gen`.

## Use

```yaml
# giant.yaml
workspace: { name: example }
std: { ref: v1 }
generate:
  - { script: gen.star, infix: codegen }
```

```python
# gen.star
load("@std//controllergen.star", "controllergen_targets")

def generate(ws):
    controllergen_targets(ws, api_root = "api")
```

Two conventions drive it:

- A directory containing `zz_generated.deepcopy.go` gets a `deepcopy`
  target regenerating it in place (`controller-gen object`); where
  `zz_generated.conversion.go` also exists, conversion-gen is chained.
- Every API group under `api_root` - a directory whose subtree holds
  `*_types.go` - gets a `crd-<group>` target writing YAML under
  `output/crds/<group>`.

For a tree with `api/iam/v1/user_types.go` and a marked
`internal/types/`, `giant gen` writes:

```yaml
# internal/types/giant.codegen.yaml
targets:
- name: deepcopy
  inputs:
  - //internal/types/*.go
  outputs:
  - //internal/types/zz_generated.deepcopy.go
  - //internal/types/zz_generated.conversion.go
  command: controller-gen object paths=. output:dir=. && conversion-gen
    --output-file=zz_generated.conversion.go .
  cache: true
  tags: [codegen, deepcopy]
```

```yaml
# api/iam/giant.codegen.yaml
targets:
- name: crd-iam
  inputs:
  - //api/iam/**/*.go
  outputs:
  - //output/crds/iam/*.yaml
  command: cd $GIANT_WORKSPACE_ROOT && controller-gen crd paths=./api/iam/...
    output:crd:dir=output/crds/iam
  cache: true
  tags: [codegen, crd]
```

Because the generated files are target *outputs*, anything that consumes
them (a Go build whose inputs glob the package) picks up an inferred
dependency on the codegen target.

## Reference

| Function | What it does |
|---|---|
| `controllergen_targets(ws, api_root, out_dir, deps, exclude_prefixes)` | The floor: deepcopy everywhere it's marked; CRDs when `api_root` is given. |
| `deepcopy_targets(ws, deps, exclude_prefixes)` | Just the deepcopy/conversion convention. `exclude_prefixes` (default `vendor/`, `third-party/`) skips trees you don't own. |
| `crd_targets(ws, api_root, out_dir, deps)` | Just the per-group CRD convention. |

`controller-gen` and `conversion-gen` are expected on PATH (your toolchain
target or dev shell provides them).
