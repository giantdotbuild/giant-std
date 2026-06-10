# docker.star

Docker image targets. The unit is the image; the Dockerfile is one of its
parameters - a repo where every component has its own Dockerfile and a repo
where many components share one parameterized template are the same
`docker_image()` call with different arguments.

Image bytes live in the Docker daemon, not giant's cache, so image targets
carry no outputs: each build tags the image with giant's cache key and an
`exists` check skips the build when that exact tag is already present. A
changed input (the Dockerfile, the copied artifact, a build arg) produces a
new key and rebuilds.

## Co-located Dockerfiles

```python
# gen.star
load("@std//docker.star", "dockerfile_targets")

def generate(ws):
    dockerfile_targets(ws, repo = "registry.example.com/svc/")
```

One image target per directory holding a Dockerfile, named after the
directory. For `svc/api/Dockerfile`, `giant gen` writes:

```yaml
# svc/api/giant.docker.yaml
targets:
- name: image
  inputs:
  - //svc/api/Dockerfile
  - //svc/api/**/*
  command: docker build -f svc/api/Dockerfile -t registry.example.com/svc/api:$GIANT_CACHE_KEY svc/api
  cwd: //
  cache: false
  sandbox: false
  exists: docker image inspect registry.example.com/svc/api:$GIANT_CACHE_KEY >/dev/null 2>&1
  tags: [kind=image]
```

Pass `image_for` (a function `dir -> image`) when the naming rule is richer
than `repo + basename`.

## A shared template

Many services, one parameterized Dockerfile that COPYs a prebuilt binary:

```python
load("@std//docker.star", "docker_image")

def generate(ws):
    docker_image(
        name = "image",
        image = "registry.example.com/cloud/api",
        context = "out",
        dockerfile = "build/Dockerfile.bin",
        args = {"OUTPUT_NAME": "api"},
        inputs = ["//out/bin/api"],
        package = "cmd/api",
        push = True,
    )
```

Naming the copied artifact in `inputs` is what links the image to the
target that builds the binary - giant's input/output inference adds the
dependency, so `giant build //cmd/api:image` compiles the binary first.
With `push = True` the cache-key tag is pushed and the `exists` check asks
the registry (`docker manifest inspect`) instead of the local daemon.

Tagging a human-facing name (`latest`, a git sha) is a deploy step, not a
build step; do it where you deploy, against the cache-key tag.

## The tree rule

`nearest_dockerfile(ws, dir, stop)` walks up from a component looking for a
Dockerfile, bounded at `stop`. Use it to let a component override a shared
template just by having a Dockerfile in or above its directory - deleting
the file opts back into the template:

```python
load("@std//docker.star", "docker_image", "nearest_dockerfile")

def image_target(ws, dir, name):
    df = nearest_dockerfile(ws, dir, stop = "svc") or "build/Dockerfile.bin"
    docker_image(
        name = "image",
        image = "registry.example.com/" + name,
        context = "out",
        dockerfile = df,
        args = {"OUTPUT_NAME": name},
        inputs = ["//out/bin/" + name],
        package = dir,
    )
```

## Reference

| Function | What it does |
|---|---|
| `docker_image(name, image, context, ...)` | Emit one image target. `dockerfile` defaults to `<context>/Dockerfile`; `inputs` defaults to everything under the context (pass the artifact list explicitly for shared output dirs); `args` become `--build-arg`s; `push` pushes the cache-key tag. |
| `dockerfile_targets(ws, repo, glob, image_for, ...)` | The co-located convention over a glob. |
| `nearest_dockerfile(ws, dir, stop, name)` | Nearest Dockerfile walking up, or None. |

All paths are workspace-relative; targets run from the workspace root, are
uncached (`exists` is the cache), and sandbox-exempt (they talk to the
daemon).
