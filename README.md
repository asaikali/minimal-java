# minimal-java

Experiments in building minimal, secure, and reproducible Java container runtimes.

A hands-on, teaching-oriented project showing how small, secure, and fast a Java
web app's container can get — built up **one technique at a time**.

The application is a typical Spring Boot 4 service: Java 25, Spring MVC exposing a
REST API, backed by Spring Data JPA / Hibernate over an H2 database with Flyway
migrations (it returns a random quote). It's intentionally small so the focus stays
on the **`Dockerfile`**, which defines a *series* of images, each adding one
focused technique, so you can see what each step costs and what it contributes.

## Highlights

- **~2.5 MB base** — chiseled Ubuntu: no shell, no package manager, `libc6` only.
- **~119 MB for the whole app** — a complete Spring Boot 4 service.
- **~3.6× faster startup** — ~1.8 s → ~0.5 s via a JDK 25 AOT cache.
- **Multi-arch** — `linux/amd64` + `linux/arm64` from one command.
- **Reproducible & self-contained** — in-container build, pinned versions.

## The image series

`./build-image.sh` produces five images. `fat` is the naive baseline — the Spring
Boot fat jar on the full Temurin JRE, with none of the techniques applied. The
rest are the chiseled series: `ubuntu` and `jre` build up the runtime in a line,
then `app` and `aot` are two **sibling** packagings of the same Spring Boot app on
top of `jre` — `app` favors a smaller image, `aot` trades a larger image for
faster startup (full `ubuntu:26.04` is shown only for comparison):

```
eclipse-temurin:25-jre (full)
└─ fat       Spring Boot fat jar, no techniques  — the naive baseline

scratch
└─ ubuntu    chiseled Ubuntu (base-files + libc6)
   └─ jre     trimmed Temurin JRE 25
      ├─ app   exploded Spring Boot app           — smaller image
      └─ aot   app layout + JDK 25 AOT cache      — faster startup, larger image
```

| Image                 | Builds on | Adds (the technique)                                                       | Size (amd64) | Startup |
| --------------------- | --------- | -------------------------------------------------------------------------- | ------------ | ------- |
| `ubuntu:26.04` (full) | —         | the whole distro, for reference                                            | ~42 MB       | —       |
| `minimal-java:fat`    | full JRE  | **naive baseline** — fat jar on the full Temurin JRE, no techniques        | ~170 MB      | ~2.2 s  |
| `minimal-java:ubuntu` | `scratch` | Canonical **chisel** — built bottom-up from package *slices* (no shell/apt) | ~2.5 MB     | —       |
| `minimal-java:jre`    | `:ubuntu` | **trimmed Temurin JRE 25** — standalone launchers removed                  | ~65 MB       | —       |
| `minimal-java:app`    | `:jre`    | Spring Boot **layered jar**, exploded into cache-friendly layers           | ~119 MB      | ~1.8 s  |
| `minimal-java:aot`    | `:jre`    | the app layout **plus** a **JDK 25 AOT cache** (Project Leyden)            | ~146 MB      | ~0.5 s  |

Under the hood, each image is a named stage in a single multi-stage `Dockerfile`;
`build-image.sh` builds each one with `docker buildx build --target <name>`,
multi-arch for `linux/amd64` + `linux/arm64`. The **Size** column is what
`compare-image-sizes.sh` prints; the **Startup** column is what
`compare-startup-times.sh` reports (Spring Boot's own startup time) — both
reproducible on your own machine. `compare-cve-counts.sh` does the same for the
security story, reporting Docker Scout's CVE counts per image (the OS attack
surface drops to zero at the chiseled `ubuntu`/`jre` layers).

See **[Resources](#resources)** below for talks that go deep on chisel and AOT.

## Quick start

```bash
./build-image.sh        # build ubuntu/jre/app/aot multi-arch + print the size comparison
./run-aot.sh            # run minimal-java:aot -> http://localhost:8080
curl localhost:8080     # {"author":"...","id":N,"quote":"..."}
```

Each part of the workflow is also its own script, runnable on its own:

```bash
./run-app.sh                              # run the app image (no AOT) instead of aot
./compare-image-sizes.sh                  # re-print the size comparison (no rebuild)
./compare-startup-times.sh                # compare startup time: app vs aot
./compare-cve-counts.sh                   # compare CVE counts across the series (Docker Scout)
./push-image.sh ghcr.io/you/minimal-java  # publish the built series to a registry
```

## Resources

Background material on the topics this repo explores.

### Chisel & minimal Ubuntu containers (the `ubuntu` image)

Three talks explain the tooling behind our chiseled `ubuntu` base image — how to
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
    what our `ubuntu`/`jre` images already are. Chisel can also emit a **manifest**
    (`manifest.wall`, JSON-lines) listing every file/package/version for SBOMs.
  - **Maintainability pull-through:** slices ride Ubuntu's normal package build/CI, so
    security patches (LTS/ESM) flow into chiseled images like any other Ubuntu update —
    you don't lose the distro's maintenance by going minimal.
  - **Results:** for Python 3.11, full Ubuntu-based ~43 MB → distroless (`bare`/scratch
    base) ~29 MB → **chiseled ~14–16 MB**, with a ~60% CVE reduction, ~20–25% faster
    pull/spin-up, and FIPS/STIG-friendly output.
  - **Two ways to use it:** with a plain multi-stage Dockerfile (`chisel cut` into a
    rootfs, then `COPY` it onto `scratch` — exactly what this repo's `ubuntu` stage
    does), or declaratively via Canonical's **Rockcraft** (+ **Pebble** as the init /
    entrypoint), which produces images called "rocks".

### Project Leyden & AOT (the `aot` image)

- **[Supercharge your JVM performance with Project Leyden and Spring Boot](https://www.youtube.com/watch?v=UqaSWiE076w)**
  — by **Moritz Halbritter** (Spring Boot engineering team). This recording is the
  Devoxx CERN delivery (2026-02-10), a newer run than the earlier Devoxx Belgium one,
  uploaded a few weeks after the talk.

  A practical walkthrough of how to cut JVM startup ~4x today using only stock
  **JDK 25 + Spring Boot 4** — no preview flags, no GraalVM, no custom JDK. This is
  the technique our `aot` image implements. Summary:

  - **Project Leyden** improves startup/warm-up by *shifting work earlier in time*
    (from runtime to build time) via a **training run** that observes the app, so
    class loading/linking (and, in JDK 25, JIT profiling) don't have to be redone on
    every boot. Leyden features ship in the mainline JDK — a Leyden-enabled JVM still
    behaves exactly like a normal JVM (reflection, serialization, etc. all work).
  - **AOT cache** (JEP 483, JDK 24; the successor to CDS) records class
    loading + linking during a training run and replays it at runtime. **JDK 25** adds
    *AOT method profiling* (warm-up improvement) and *command-line ergonomics*
    (JEP 514): a one-step `-XX:AOTCacheOutput=app.aot` to create the cache and
    `-XX:AOTCache=app.aot` to use it (the old separate `.aotconf` step is gone).
  - **Constraints:** the cache requires the *same JVM down to the point release* and
    same arch/OS; the classpath must be a **list of jars** (no directories, wildcards,
    or nested jars) and the deployment classpath must be a superset of the training
    one. If anything mismatches, the JVM simply **ignores the cache and starts
    normally** — it never crashes. (Jar timestamps must be preserved when copying.)
  - **Why Spring Boot needs the layered-jar extract:** Boot's fat jar uses nested jars
    via a custom classloader, which the AOT cache doesn't support — so you extract it
    with `-Djarmode=tools ... extract`. Extracting *alone* already shaves ~600ms by
    dropping the nested-jar classloader overhead.
  - **"Poor man's training run":** `-Dspring.context.exit=onRefresh` boots the context,
    instantiates singleton beans, then exits *before* the web server starts — enough to
    capture most class loading, and trivial to run at image-build time.
  - **Results (Pet Clinic, time-to-first-request):** fat jar ~3.0s → extracted ~2.4s →
    `+ AOT cache` ~0.96s (~3.1x) → `+ Spring AOT` ~0.75s (~4x). CPU time consumed during
    startup (what cloud providers bill) drops ~2.6x.
  - **Spring AOT** is separate from the JVM's AOT cache: it generates code for the bean
    arrangement (originally for GraalVM native image) and also speeds JVM startup; the
    trade-off is the bean arrangement is frozen at build time.
  - **For warm-up (peak throughput), not just startup,** you need a *real* training run
    that exercises hot paths with production-like load — harder to set up than the poor
    man's run. **What's next** in the Leyden prototype: ahead-of-time *code* compilation
    (store compiled machine code in the cache → ~0.45s startup / ~5x, with
    portability/instruction-set trade-offs), AOT for user-defined classloaders (may
    remove the extract step), AOT object caching with any GC (JDK 26), and modular
    Spring AOT.
