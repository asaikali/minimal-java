# Part 2 — A smaller, better-layered image

> **minimal-java tutorial** · [← Part 1](1-pipeline.md) · **Part 2** · [Part 3 — a faster app →](3-speed.md) · [↑ Overview](../README.md)

[Part 1](1-pipeline.md) shipped `fat`: ~165 MB, the full Temurin JRE on a full OS,
running as root. The app is fine — the **packaging** is wasteful. This part answers
**"can the image be better?"** with three moves that don't touch the application:

1. a **chiseled** OS base instead of a full distro,
2. a **trimmed JRE** instead of the full one,
3. the Spring Boot jar **exploded into cache-friendly layers** instead of one fat jar.

It also introduces a new pipeline — because once we stop using the upstream full JRE,
*someone* has to build the base.

## Move 1 — a chiseled Ubuntu base (and the base-images pipeline)

[`images/2-size/golden-ubuntu/Dockerfile`](../images/2-size/golden-ubuntu) builds a base from **scratch** using
Canonical's [**chisel**](https://github.com/canonical/chisel): instead of inflating a
full distro and trimming it, it assembles a filesystem from **slices** of Ubuntu
packages — here just `base-files` and `libc6_libs`. The result is the *real* Ubuntu
bits, but **no shell, no package manager, nothing** beyond what we asked for: ~2.5 MB.

`fat` used the *upstream* `eclipse-temurin` image, so Part 1 needed no base of our own.
Now we do — so a dedicated **base-images pipeline**
([`base-images.yml`](../.github/workflows/base-images.yml)) owns it, the way a platform
team publishes golden base images on their own schedule. It publishes
`ghcr.io/<owner>/<repo>/golden-ubuntu`, then builds the JRE base (Move 2) `FROM` that base
**pinned by digest**:

```
  images/2-size/golden-ubuntu  ──▶  ghcr.io/<owner>/<repo>/golden-ubuntu
  images/2-size/golden-jre     ──▶  ghcr.io/<owner>/<repo>/golden-jre      (FROM golden-ubuntu@sha256:…)
```

Pinning by digest (not a floating tag) means the published `golden-jre` records *exactly*
which base it sits on — the provenance the whole repo is about. Locally,
`build-images.sh` does the same hand-off through the daemon's image store, and the
Dockerfile takes an `ARG UBUNTU_BASE` that defaults to the local tag so offline builds
just work.

That's why they're called **golden** images — they're the platform's owned, named,
published base *products*, not incidental build artifacts. The same discipline applies
one level up: each golden image **pins its own upstream root by digest** too —
`FROM ubuntu:${UBUNTU_VERSION}@sha256:…` and
`FROM eclipse-temurin:${JAVA_VERSION}-jre@sha256:…` — so the whole chain is reproducible
end to end, and [Renovate](renovate.md) keeps those digests current automatically.
(The naive `fat` image from [Part 1](1-pipeline.md) deliberately *doesn't* pin — "the
baseline doesn't even do this" is part of the point.) A real platform team would publish
these golden images from a central registry their app teams build on; here they live
under the same repo's ghcr namespace for simplicity.

## Move 2 — a trimmed JRE

[`images/2-size/golden-jre/Dockerfile`](../images/2-size/golden-jre) takes the official Temurin JRE, drops the
standalone launchers a running service never invokes (`jfr`, `jrunscript`,
`jwebserver`, `keytool`, `rmiregistry`), and copies just the runtime onto the chiseled
base. `libc6` (from the golden-ubuntu base) is the only dependency it needs. Result: ~65 MB,
still no shell or package manager.

## Move 3 — explode the Spring Boot jar into layers

[`images/2-size/app/Dockerfile`](../images/2-size/app) builds `FROM` the `golden-jre` base and, instead of
copying one fat jar, extracts the Spring Boot **layered** jar and copies each layer
separately, ordered slowest-changing first:

```dockerfile
COPY --from=extract /build/extracted/dependencies/ ./          # change rarely
COPY --from=extract /build/extracted/spring-boot-loader/ ./
COPY --from=extract /build/extracted/snapshot-dependencies/ ./
COPY --from=extract /build/extracted/application/ ./           # change every commit
```

A code change then only busts the small final layer; the big dependency layers stay
cached. The jar still comes from Part 1's artifact pipeline (the Dockerfile only
`COPY`s) — the `extract` runs once on the native arch since the layers are
architecture-independent.

## Measure it — size

```bash
./scripts/image-sizes.sh
```

```
Size comparison (image size, decimal MB):

  image                            amd64       arm64
  ubuntu:26.04 (full)            41.6 MB     40.7 MB
  minimal-java/golden-ubuntu      2.5 MB      1.7 MB
  minimal-java/golden-jre        65.4 MB     63.5 MB
  minimal-java/fat (naive)      165.5 MB    163.6 MB
  minimal-java/app              114.0 MB    112.0 MB
```

Full Ubuntu is **~42 MB**; the chiseled base is **~2.5 MB** — same real bits, only the
slices we asked for. The whole app (`app`) lands at **~114 MB**, **smaller than the
naive `fat` baseline (~165 MB)** which carried the full JRE *and* the unexploded fat
jar. Same application, ~50 MB lighter.

## Measure it — CVEs

```bash
./scripts/cve-counts.sh        # needs trivy + jq
```

```
=== CVE summary (Trivy — counts per severity) ===
  image                         C    H    M    L
  ubuntu:26.04                  0    8   56    3
  minimal-java/golden-ubuntu           0    0    0    0
  minimal-java/golden-jre              0    0    0    0
  minimal-java/fat              3   11   62    4
  minimal-java/app              3    3    0    1
```

This is the real payoff. Full `ubuntu:26.04` carries dozens of OS findings; the
chiseled `golden-ubuntu` and `golden-jre` report **zero** — those packages simply aren't in the
image. The naive `fat` inherits the full JRE's OS packages on top of the app's jars
(62 medium findings alone). `app` keeps the OS at **zero**; its remaining findings live
in the **Java dependencies**, exactly what you'd triage by updating dependencies — not
OS cruft you can't see.

## Run it — now hardened

In Part 1, `run-fat.sh` ran plainly, as root. `app` is built non-root (numeric
`USER 10001:10001`, no `/etc/passwd` needed), and [`run-app.sh`](../scripts/run-app.sh)
runs it the way you'd want in production:

```bash
./scripts/run-app.sh
```

```bash
$ docker inspect -f 'User={{.Config.User}} ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} CapDrop={{.HostConfig.CapDrop}}' minimal-java-app
User=10001:10001 ReadonlyRootfs=true CapDrop=[ALL]
```

Non-root UID, read-only root filesystem, every Linux capability dropped,
`no-new-privileges`. The chiseled image has no shell for an attacker to reach, and the
JVM only needs a writable `/tmp` (an in-memory `--tmpfs`). Compare that to `fat`'s
plain root run — that's what proper packaging buys.

## How to properly layer a Spring Boot app

Putting the three moves together, a production-grade Spring Boot image is:

- built **`FROM` a minimal, CVE-free base** (chiseled Ubuntu + a trimmed JRE), owned by
  a base-image pipeline and **digest-pinned**;
- the jar **exploded into Spring Boot layers**, copied slowest-changing first for cache
  reuse;
- run **non-root, read-only, with all capabilities dropped**.

Same app as `fat`, but smaller, with zero OS CVEs, and hardened.

Next: it's small and safe — but startup is still ~1.6 s. **Can we make it faster?**
That's [Part 3](3-speed.md).

## Resources — chisel & minimal Ubuntu containers

<details>
<summary>Three talks (shortest → longest) + a combined summary of the key ideas</summary>

Three talks explain the tooling behind our chiseled `golden-ubuntu` base image — how to
build distroless-style Ubuntu images that keep only the files you need. If you're
new to chisel, watch them **shortest → longest**; each adds more depth:

1. **[Chiselled Ubuntu Containers](https://www.youtube.com/watch?v=o8NILnbjhQ4)**
   — Mark Lewis, Canonical · lightboard explainer · ~7 min. The quickest "what &
   why": the extensibility-vs-security trade-off, what gets dropped for production
   (no shell, no package manager, no privileged user), and how slices solve it.
   Best starting point.
2. **[Re-inventing distroless with Chiselled Ubuntu containers](https://www.youtube.com/watch?v=yQukQb-n99E)**
   — Canonical, Ubuntu Summit 2024 · ~20 min · clearest audio. Good second watch:
   the distroless "false negatives" problem in CVE scanners, slice definition files
   and `chisel cut`, with live demos. Start here if you want just one talk.
3. **[Chisel: a bottom up build strategy for minimal and secure Ubuntu containers](https://www.youtube.com/watch?v=Vr6AIGJw3xg)**
   — Canonical, OCX 2024 (Eclipse Foundation) · ~26 min. A useful deeper complement
   covering the full Rockcraft + Chisel + Pebble toolchain and size/CVE comparisons.

Combined summary of the key ideas:

  - **The problem:** a normal `FROM ubuntu` + `apt install` image drags in distro
    residue you never use at runtime (shells, `awk`/`grep`/`ls`, the package manager
    and its caches) — e.g. ~43 MB for a Python image. Top Docker Hub images routinely
    ship CVEs that take ~3 weeks to patch, and hand-rolling a *minimal* image is hard
    to get right and maintain.
  - **Top-down distroless is hard:** the multi-stage "copy only what you need onto
    `scratch`" approach forces you to figure out every required file and dependency
    (e.g. CPython's `libc` and friends) by hand. Google's Bazel-based distroless images
    are tiny (~20 MB) but the recipes are long and pull in Bazel.
  - **Chisel is bottom-up instead:** rather than inflate a base and trim it, you start
    from `scratch` and assemble a filesystem from **slices** of Ubuntu packages. The
    bits are the *real* Ubuntu bits, so anything that runs on Ubuntu runs on the
    chiseled image — but only the files you asked for are present, shrinking both size
    and attack surface.
  - **Slices & slice definition files:** chisel resolves slice dependencies
    automatically/recursively from slice-definition files. Standard slice names are
    `bins` (executables), `libs` (shared libraries), `data` (static data), `config`
    (editable config), and `copyright` (auto-included for license compliance) — which
    is exactly why this repo cuts `base-files_base`, `base-files_release-info`, and
    `libc6_libs`.
  - **Hand-rolled distroless can hide CVEs:** scanners identify vulnerabilities from
    package metadata left in the image. Cherry-picking files onto `scratch` can drop
    that metadata, so scanners report *false negatives* — removing a single file made
    multiple scanners report zero CVEs. Chisel keeps the real package provenance, so
    scanning stays honest.
  - **Production-grade defaults:** the talks argue a production container shouldn't have
    a shell, a package manager, or privileged users, and should be immutable — close to
    what our `golden-ubuntu`/`golden-jre` images already are. Chisel can also emit a **manifest**
    (`manifest.wall`, JSON-lines) listing every file/package/version for SBOMs.
  - **Maintainability pull-through:** slices ride Ubuntu's normal package build/CI, so
    security patches (LTS/ESM) flow into chiseled images like any other Ubuntu update —
    you don't lose the distro's maintenance by going minimal.
  - **Results:** for Python 3.11, full Ubuntu-based ~43 MB → distroless (`bare`/scratch
    base) ~29 MB → **chiseled ~14–16 MB**, with a ~60% CVE reduction, ~20–25% faster
    pull/spin-up, and FIPS/STIG-friendly output.
  - **Two ways to use it:** with a plain multi-stage Dockerfile (`chisel cut` into a
    rootfs, then `COPY` it onto `scratch` — exactly what this repo's `golden-ubuntu` image
    does), or declaratively via Canonical's **Rockcraft** (+ **Pebble** as the init /
    entrypoint), which produces images called "rocks".

</details>

---

> **Next:** [Part 3 — a faster app →](3-speed.md)
