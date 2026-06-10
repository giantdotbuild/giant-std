# controllergen.star - kubebuilder codegen targets (controller-gen,
# conversion-gen), derived from source conventions rather than sidecar
# config.
#
# Part of giant's official Starlark std collection: reach it with
# `load("@std//controllergen.star", ...)`, or vendor it with
# `giant gen vendor controllergen.star`.
#
# The conventions are the kubebuilder ecosystem's own marker files:
#
#   - A directory containing `zz_generated.deepcopy.go` is a controller-gen
#     object package; the target regenerates that file in place. Where
#     `zz_generated.conversion.go` also exists, conversion-gen runs too.
#   - An API group is a directory under `api_root` whose versions hold
#     `*_types.go` files; each group gets a CRD-generation target writing
#     YAML under `out_dir/<group>`.
#
# Both detect from the tree, so adding a new API type or group needs no
# generator edits - the next `giant gen` picks it up.

# A regenerate-in-place target per directory carrying a deepcopy marker.
# `exclude_prefixes` skips trees you don't own (vendored code ships its
# markers too).
def deepcopy_targets(ws, deps = [], exclude_prefixes = ["vendor/", "third-party/"]):
    conversion = {}
    for f in ws.glob("**/zz_generated.conversion.go"):
        conversion[_dir(f)] = True
    for f in sorted(ws.glob("**/zz_generated.deepcopy.go")):
        d = _dir(f)
        if [p for p in exclude_prefixes if d.startswith(p)]:
            continue
        outputs = ["//" + d + "/zz_generated.deepcopy.go"]
        cmd = "controller-gen object paths=. output:dir=."  # cwd is the package dir
        if d in conversion:
            outputs.append("//" + d + "/zz_generated.conversion.go")
            cmd += " && conversion-gen --output-file=zz_generated.conversion.go ."
        target(
            name = "deepcopy",
            command = cmd,
            inputs = ["//" + d + "/*.go"],
            outputs = outputs,
            deps = deps,
            cache = True,
            tags = ["codegen", "deepcopy"],
            package = d,
        )

# A CRD-generation target per API group under `api_root` (e.g. "api" or
# "pkg/apis"): every directory there whose subtree holds `*_types.go`.
# Output YAML lands under `out_dir/<group>`.
def crd_targets(ws, api_root, out_dir = "output/crds", deps = []):
    root = api_root.rstrip("/")
    groups = {}
    for f in ws.glob(root + "/**/*_types.go"):
        rest = f[len(root) + 1:]
        if "/" in rest:
            groups[rest.split("/")[0]] = True
    for g in sorted(groups.keys()):
        base = root + "/" + g
        target(
            name = "crd-" + g,
            command = "cd $GIANT_WORKSPACE_ROOT && controller-gen crd paths=./" +
                      base + "/... output:crd:dir=" + out_dir + "/" + g,
            inputs = ["//" + base + "/**/*.go"],
            outputs = ["//" + out_dir + "/" + g + "/*.yaml"],
            deps = deps,
            cache = True,
            tags = ["codegen", "crd"],
            package = base,
        )

# The floor: deepcopy everywhere it's marked, CRDs when an `api_root` is
# given.
def controllergen_targets(ws, api_root = None, out_dir = "output/crds", deps = [],
                          exclude_prefixes = ["vendor/", "third-party/"]):
    deepcopy_targets(ws, deps, exclude_prefixes)
    if api_root:
        crd_targets(ws, api_root, out_dir, deps)

def _dir(f):
    return f[:f.rfind("/")] if "/" in f else ""
