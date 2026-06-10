# docker.star - Docker image targets over the host primitives.
#
# Part of giant's official Starlark std collection: reach it with
# `load("@std//docker.star", ...)`, or `giant gen vendor docker.star` to copy
# it into your repo's `star/` for editing.
#
# The unit here is the image, and the Dockerfile is one of its parameters -
# a repo where every component has its own Dockerfile and a repo where many
# components share one parameterized template are the same `docker_image()`
# call with different arguments. Image bytes live in the Docker daemon, so
# targets carry no outputs and key the daemon's copy by the giant cache key
# (`exists` + a `$GIANT_CACHE_KEY` tag): an unchanged image is a skip, a
# changed input rebuilds it.
#
# All paths (dockerfile, context) are workspace-relative; targets run from
# the workspace root.

# Emit one image target. The floor for any convention.
#
#   docker_image(
#       name = "api",
#       image = "registry.example.com/cloud/api",
#       context = "out/linux-amd64",
#       dockerfile = "build/Dockerfile.go_bin",
#       args = {"OUTPUT_NAME": "api"},
#       inputs = ["//out/linux-amd64/bin/api"],
#   )
#
# `inputs` should name what the build COPYs in (the artifact, configs); the
# dockerfile is always added. When `inputs` is None, everything under the
# context is the input - right for small co-located contexts, too broad for
# an output dir shared by many images. Listing a produced artifact as an
# input is what links the image to the target that builds the artifact
# (giant's input/output inference).
#
# `push = True` appends a push of the cache-key tag; tagging a human-facing
# name (latest, a git sha) is a deploy step, not a build step, and stays out.
def docker_image(
        name,
        image,
        context,
        dockerfile = None,
        args = {},
        inputs = None,
        deps = [],
        package = None,
        push = False,
        tags = []):
    ctx = _norm(context)
    df = _norm(dockerfile) if dockerfile else _join(ctx, "Dockerfile")
    build = "docker build -f " + df
    for k in sorted(args.keys()):
        build += " --build-arg " + k + "='" + args[k] + "'"
    build += " -t " + image + ":$GIANT_CACHE_KEY " + (ctx if ctx else ".")
    if push:
        build += " && docker push " + image + ":$GIANT_CACHE_KEY"
    ins = ["//" + df]
    if inputs == None:
        ins.append("//" + _join(ctx, "**/*"))
    else:
        ins += inputs
    target(
        name = name,
        command = build,
        cwd = "//",
        inputs = ins,
        outputs = [],
        deps = deps,
        cache = False,
        # Skip when this exact build already exists: in the daemon, or - when
        # pushing - in the registry (manifest inspect needs pull access).
        exists = ("docker manifest inspect " if push else "docker image inspect ") +
                 image + ":$GIANT_CACHE_KEY >/dev/null 2>&1",
        # The build talks to the docker daemon and may pull base layers;
        # neither survives confinement.
        sandbox = False,
        tags = ["kind=image"] + tags,
        package = package if package != None else ctx,
    )

# The nearest Dockerfile walking up from `dir` to `stop` (both
# workspace-relative; `stop` must be `dir` or one of its ancestors). Returns
# its workspace-relative path, or None. This is the tree-placement rule: a
# Dockerfile in or above a component opts it out of the shared template,
# and deleting the file opts back in.
def nearest_dockerfile(ws, dir, stop = "", name = "Dockerfile"):
    d = _norm(dir)
    stop = _norm(stop)
    for _ in range(len(d.split("/")) + 1):
        candidate = _join(d, name)
        if ws.glob(candidate):
            return candidate
        if d == stop or d == "":
            break
        d = "/".join(d.split("/")[:-1])
    return None

# The glob convention: one image per directory holding a Dockerfile, context
# = that directory, named after it. For repos that keep Dockerfiles next to
# the code. `repo` prefixes the image name (`repo + dir basename`); pass
# `image_for` (a function dir -> image) when the naming rule is richer.
def dockerfile_targets(ws, repo, glob = "**/Dockerfile", image_for = None, deps = [], push = False):
    for df in sorted(ws.glob(glob)):
        dir = "/".join(df.split("/")[:-1])
        base = dir.split("/")[-1] if dir else "image"
        image = image_for(dir) if image_for else repo + base
        docker_image(
            name = "image",
            image = image,
            context = dir,
            dockerfile = df,
            deps = deps,
            push = push,
        )

def _norm(p):
    if p == None or p == "." or p == "//":
        return ""
    if p.startswith("//"):
        p = p[2:]
    return p.rstrip("/")

def _join(dir, rest):
    return dir + "/" + rest if dir else rest
