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
- **~4.8× faster startup** — ~2.0 s → ~0.4 s via a JDK 25 AOT cache + Spring AOT.
- **Multi-arch** — `linux/amd64` + `linux/arm64` from one command.
- **Reproducible & self-contained** — in-container build, pinned versions.
- **Supply-chain ready** — every image carries an SBOM + SLSA build provenance
  attestation (inspect with `docker buildx imagetools inspect` once pushed).

## The image series

`build-images.sh` produces six images. `fat` is the naive baseline — the Spring
Boot fat jar on the full Temurin JRE, with none of the techniques applied. The
rest are the chiseled series: `ubuntu` and `jre` build up the runtime in a line,
then `app`, `jvm-aot`, and `spring-aot` are three **sibling** packagings of the same
Spring Boot app on top of `jre` — `app` favors a smaller image, `jvm-aot` adds a JDK
AOT cache for faster startup, and `spring-aot` stacks **Spring AOT** on top of the
AOT cache for the fastest startup (full `ubuntu:26.04` is shown only for
comparison):

```
eclipse-temurin:25-jre (full)
└─ fat       Spring Boot fat jar, no techniques  — the naive baseline

scratch
└─ ubuntu    chiseled Ubuntu (base-files + libc6)
   └─ jre     trimmed Temurin JRE 25
      ├─ app         exploded Spring Boot app                — smaller image
      ├─ jvm-aot     app layout + JDK 25 AOT cache           — faster startup
      └─ spring-aot  jvm-aot layout + Spring AOT             — fastest startup
```

| Image                     | Builds on | Adds (the technique)                                                       | Size (amd64) | Startup |
| ------------------------- | --------- | -------------------------------------------------------------------------- | ------------ | ------- |
| `ubuntu:26.04` (full)     | —         | the whole distro, for reference                                            | ~42 MB       | —       |
| `minimal-java:ubuntu`     | `scratch` | Canonical **chisel** — built bottom-up from package *slices* (no shell/apt) | ~2.5 MB     | —       |
| `minimal-java:jre`        | `:ubuntu` | **trimmed Temurin JRE 25** — standalone launchers removed                  | ~65 MB       | —       |
| `minimal-java:fat`        | full JRE  | **naive baseline** — fat jar on the full Temurin JRE, no techniques        | ~170 MB      | ~2.0 s  |
| `minimal-java:app`        | `:jre`    | Spring Boot **layered jar**, exploded into cache-friendly layers           | ~119 MB      | ~1.6 s  |
| `minimal-java:jvm-aot`    | `:jre`    | the app layout **plus** a **JDK 25 AOT cache** (Project Leyden)            | ~146 MB      | ~0.5 s  |
| `minimal-java:spring-aot` | `:jre`    | the `jvm-aot` layout **plus Spring AOT** — generated bean wiring            | ~145 MB      | ~0.4 s  |

Under the hood, each image is a named stage in a single multi-stage `Dockerfile`;
`build-images.sh` builds each one with `docker buildx build --target <name>`,
multi-arch for `linux/amd64` + `linux/arm64`. The **Size** column is what
`image-sizes.sh` prints; the **Startup** column is what
`startup-times.sh` reports (Spring Boot's own startup time) — both
reproducible on your own machine. `cve-counts.sh` does the same for the security
story, counting CVEs per image (the OS attack surface drops to zero at the
chiseled `ubuntu`/`jre` layers).

See **[Resources](#resources)** below for talks that go deep on chisel and AOT.

## JVM AOT vs Spring AOT

The `jvm-aot` and `spring-aot` images both cut startup, but with two **different**
techniques that stack — and Spring AOT carries a trade-off worth understanding
before you reach for it.

- **JVM AOT** (`jvm-aot`) is a **JVM** feature: the Project Leyden **AOT cache**
  (JEP 514). A build-time *training run* records class loading + linking (and, on
  JDK 25, method profiling), and the runtime replays it instead of redoing the work
  on every boot. It's framework-agnostic and leaves your application code and bean
  graph exactly as they are — **nothing about your app is frozen.**
- **Spring AOT** (`spring-aot`) is a **Spring** feature: at build time it generates
  Java code for the bean wiring (replacing reflection-based context setup) and
  **freezes the bean arrangement** — *which beans exist and how they're wired is
  decided at build time and cannot change at runtime.*

`spring-aot` uses **both**, applied in this order — which is why it's the fastest
image:

1. **Spring AOT runs first**, at the Maven build (`-Pspringaot` → `process-aot`),
   baking the generated bean-wiring code into the jar.
2. **Then the JVM AOT cache training run** boots that *already-Spring-AOT-processed*
   app (`-Dspring.aot.enabled=true -Dspring.context.exit=onRefresh`) and records its
   class loading/linking into `app.aot`.
3. **At runtime** the JVM replays `app.aot` *and* Spring uses the generated wiring.

Because the training run observes the Spring-AOT-optimized startup, the Leyden cache
captures *that* leaner path — so the two compound rather than just coexist. (The
`jvm-aot` image is the same minus step 1: no Spring AOT, so its training run records
the ordinary reflection-based startup.)

But that frozen bean arrangement is the catch. The line to keep in mind:

| Decided at **build time** — frozen by Spring AOT | Still resolved at **runtime** |
| --- | --- |
| *Which beans exist / how they're wired* — `@Profile`, `@ConditionalOnProperty`, autoconfiguration conditions | *Config values* — `application.yml`, `application-{profile}.yml`, env vars, `@Value`, `@ConfigurationProperties` |

### A concrete example

Say a `SignupService` sends email, wired differently per environment — a stub in
dev/test so you never send real mail, the real client in prod:

```java
@Profile("!prod")   // dev, test, CI
@Bean EmailSender loggingEmailSender() { return new LoggingEmailSender(); }   // just logs

@Profile("prod")
@Bean EmailSender sesEmailSender()     { return new SesEmailSender(...); }    // real AWS SES
```

**With `jvm-aot` (or no AOT):** you ship one image and pick the bean at startup with
`--spring.profiles.active=prod`. The Leyden cache never touches this — profiles stay
fully dynamic.

**With `spring-aot`:** `process-aot` evaluates `@Profile` at **build time**. If the
build ran with the default profile, the generated context contains *only*
`loggingEmailSender`; `sesEmailSender` was never generated. Run that image in prod
and either it fails at startup (no prod `EmailSender`) or — worse — **the logging
stub silently "sends" production email to a log file.** Activating `prod` at runtime
can't fix it: the bean simply doesn't exist. The same goes for any conditional bean —
a prod-only Redis cache or metrics exporter, or anything behind
`@ConditionalOnProperty(...enabled)` — the decision is made once, at build time.

Note what *still* works: because property values aren't frozen, changing
`spring.datasource.url` to point `jvm-aot`/`spring-aot` at Postgres vs MySQL is fine
under AOT — the `DataSource` bean exists either way and reads the URL at runtime.
It's bean *selection* by profile/condition that's frozen, not configuration values.

### Living with it

- **Bake in the right profile:** tell AOT which profiles to evaluate at build time —
  `<profiles>prod</profiles>` on the `process-aot` execution (see [`pom.xml`](pom.xml)) —
  or build a separate artifact per profile.
- **Design AOT-friendly:** prefer one bean whose *behavior* varies by a runtime
  **property** over two beans gated by `@Profile`; property values aren't frozen.
- **Or just use `jvm-aot`:** most of the startup win, none of the build-time freezing
  — the safe choice when the bean graph needs to stay dynamic.

This repo's app has no profiles or conditional beans, so `spring-aot` is a clean win
here; the trade-off only shows up once an app wires beans by profile or condition.
See [Project Leyden & AOT](#project-leyden--aot-the-jvm-aot-and-spring-aot-images)
for the background talk.

## Tutorial

This is a hands-on walkthrough: run each command, look at what it prints, and see
the size / startup / CVE story build up one step at a time. Every block below is
**real output** captured from this repo — your numbers will be close.

The helper scripts live in [`scripts/`](scripts). The tutorial runs them by path
from the repo root, so no extra tooling is required; if you use
[mise](https://mise.jdx.dev) it adds `scripts/` to your `PATH` after `mise trust`,
letting you drop the `./scripts/` prefix.

**Before you start** you need Docker with the **containerd image store** enabled
(Docker Desktop: *Settings → General → "Use containerd for pulling and storing
images"*). It's what lets a multi-arch image load into your local store; the
legacy store can't hold one. The CVE step also wants `trivy` and `jq`
(`brew install trivy jq`), and the Kubernetes step wants `kubectl` pointed at
Docker Desktop's cluster — both optional, only for their steps.

### Step 1 — Build the image series

Build all six images (the five chiseled targets plus the `fat` baseline),
multi-arch for `linux/amd64` + `linux/arm64`:

```bash
./scripts/build-images.sh
```

The first run creates an on-demand `chisel-builder` buildx builder, then builds
each Dockerfile target smallest-first (`ubuntu` → `jre` → `app` → `jvm-aot` →
`spring-aot` → `fat`).
You'll see BuildKit progress for each, and because the build is multi-arch, the
`jre` trim step runs *emulated* for the non-native arch — so that one is
noticeably slower on its first build. When it finishes it prints the size table
(the same one [`image-sizes.sh`](scripts/image-sizes.sh) shows on its own):

```
Size comparison (image size, decimal MB):

  image                            amd64       arm64
  ubuntu:26.04 (full)            41.6 MB     40.7 MB
  minimal-java:ubuntu             2.5 MB      1.7 MB
  minimal-java:jre               65.4 MB     63.5 MB
  minimal-java:fat (naive)      170.2 MB    168.3 MB
  minimal-java:app              118.7 MB    116.7 MB
  minimal-java:jvm-aot          145.6 MB    143.6 MB
  minimal-java:spring-aot       144.7 MB    142.8 MB
```

Read it top-down: full Ubuntu is **~42 MB**, but the chiseled `minimal-java:ubuntu`
base is **~2.5 MB** — same real Ubuntu bits, only the slices we asked for. Adding a
trimmed JRE gets you to `jre`, and the whole Spring Boot app (`app`) lands at
**~119 MB** — **smaller than the naive `fat` baseline (~170 MB)**, which carries the
full JRE *and* the unexploded fat jar. `jvm-aot` is larger than `app` by design: it
pays ~27 MB for the AOT cache to buy the startup win you'll measure in Step 4.
`spring-aot` adds Spring AOT on top of `jvm-aot` and lands about the same size (~145 MB).

### Step 2 — Run it and call the API

Start the `app` image in the foreground (Ctrl-C stops it; the container removes
itself on exit):

```bash
./scripts/run-app.sh
```

In another terminal, call the one endpoint a few times — it returns a random
quote, so the rows change:

```bash
$ curl localhost:8080
{"author":"Lord Herbert","id":5,"quote":"The shortest answer is doing"}
$ curl localhost:8080
{"author":"Vincent Lombardi","id":4,"quote":"Success demands singleness of purpose"}
```

That's a full Spring Boot 4 + JPA/Hibernate + Flyway + H2 service answering from a
**2.5 MB chiseled base** with **no shell and no package manager** inside. And
`run-app.sh` already runs it the way you'd want in production — you can confirm
the hardening on the running container:

```bash
$ docker inspect -f 'User={{.Config.User}} ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} CapDrop={{.HostConfig.CapDrop}}' minimal-java-app
User=10001:10001 ReadonlyRootfs=true CapDrop=[ALL]
```

Non-root UID, read-only root filesystem, every Linux capability dropped. Swap in
[`./scripts/run-jvm-aot.sh`](scripts/run-jvm-aot.sh) or
[`./scripts/run-spring-aot.sh`](scripts/run-spring-aot.sh) to run the fast-startup
`jvm-aot` / `spring-aot` images instead — same API, same hardening.

### Step 3 — Compare the sizes again

You already saw the table at the end of the build; re-print it any time without
rebuilding:

```bash
./scripts/image-sizes.sh
```

This reads each image's content size straight from `docker image inspect`, per
architecture — so it's a stable, reproducible number, not a parse of formatted
output.

### Step 4 — Compare startup time

Boot the `fat`, `app`, `jvm-aot`, and `spring-aot` images in turn and print Spring
Boot's own "Started" line for each:

```bash
./scripts/startup-times.sh
```

```
=== startup ===
fat: ... Started Application in 1.952 seconds (process running for 2.228)
app: ... Started Application in 1.627 seconds (process running for 1.79)
jvm-aot: ... Started Application in 0.535 seconds (process running for 0.687)
spring-aot: ... Started Application in 0.408 seconds (process running for 0.556)
```

Three techniques, three jumps. `fat → app` exploding the fat jar into layers drops
the nested-jar classloader overhead. `app → jvm-aot` the JDK 25 AOT cache replays the
class loading/linking recorded during the build-time training run — taking startup
from **~1.6 s to ~0.5 s**. `jvm-aot → spring-aot` Spring AOT replaces reflective bean
wiring with generated code, shaving it further to **~0.4 s — about 4.8× faster than
the `fat` baseline**. (Spring AOT's gain stacks on top of the AOT cache; on a larger
bean graph the gap is wider. See
[Project Leyden & AOT](#project-leyden--aot-the-jvm-aot-and-spring-aot-images) for how both are built.)

### Step 5 — Compare CVE counts

Scan every image with [Trivy](https://trivy.dev) and print a per-severity recap
(needs `trivy` and `jq`):

```bash
./scripts/cve-counts.sh
```

```
=== CVE summary (Trivy — counts per severity) ===
  image                         C    H    M    L
  ubuntu:26.04                  0    8   56    3
  minimal-java:ubuntu           0    0    0    0
  minimal-java:jre              0    0    0    0
  minimal-java:fat              3   11   62    4
  minimal-java:app              3    3    0    1
  minimal-java:jvm-aot          3    3    0    1
```

This is the security half of the story. Full `ubuntu:26.04` carries dozens of OS
findings; the chiseled `minimal-java:ubuntu` and `jre` images report **zero** —
the OS attack surface is gone because those packages simply aren't in the image.
The naive `fat` baseline inherits the full JRE's OS packages on top of the app's
jars (62 medium findings alone). The `app`/`jvm-aot` images keep the OS at zero; their
remaining findings live in the **Java dependencies** (the application jars), not
the base — exactly what you'd then triage by updating dependencies.

### Step 6 — Deploy to Kubernetes (optional)

[`k8s/deployment.yaml`](k8s/deployment.yaml) runs `minimal-java:spring-aot` on Docker
Desktop's Kubernetes, carrying the same hardening as Step 2 (non-root, read-only
root filesystem, all capabilities dropped) plus `httpGet` probes — there's no
shell in the image to run an exec health check. It uses the image you built
locally (`imagePullPolicy: IfNotPresent`, no registry needed) and exposes it on a
NodePort:

```bash
kubectl apply -f k8s/deployment.yaml
curl localhost:30080                  # -> a random quote, same as Step 2
kubectl delete -f k8s/deployment.yaml
```

### Step 7 — Publish + inspect supply-chain attestations (optional)

The build attached an SBOM and SLSA build provenance to each image. Those travel
with the image in a registry (they aren't visible on a local-only image), so push
first, then inspect:

```bash
docker login ghcr.io                  # or: gh auth token | docker login ghcr.io -u <you> --password-stdin
./scripts/push-images.sh              # retag + push the series -> ghcr.io/<owner>/<repo>
./scripts/inspect-attestations.sh     # show each image's SBOM + provenance manifests
```

With no argument both scripts derive `ghcr.io/<owner>/<repo>` from this repo's
git remote; pass a repo to override.

### Clean up

Remove everything the tutorial created locally — the `minimal-java:*` images, any
containers they left behind, and the `chisel-builder` builder (upstream base
images and anything you pushed are left alone):

```bash
./scripts/clean.sh
```

## Dependency updates

[Renovate](https://docs.renovatebot.com/) keeps the Maven deps, the Dockerfile's
base images (`ubuntu`, `eclipse-temurin`) and chisel release, the Maven wrapper,
and the GitHub Actions current — opening a PR per update and gating major bumps
behind a Dependency Dashboard checkbox. It's self-hosted, running daily via
[`.github/workflows/renovate.yml`](.github/workflows/renovate.yml). Preview what
it would propose without touching GitHub, or trigger a run on demand:

```bash
./scripts/renovate.sh       # dry-run preview against the working tree (needs Node)
./scripts/run-renovate.sh   # dispatch the workflow now and tail its logs (needs gh)
```

See **[`docs/renovate.md`](docs/renovate.md)** for the full setup, the design
decisions behind it, and the one-time GitHub App configuration a fork needs.

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

### Project Leyden & AOT (the `jvm-aot` and `spring-aot` images)

- **[Supercharge your JVM performance with Project Leyden and Spring Boot](https://www.youtube.com/watch?v=UqaSWiE076w)**
  — by **Moritz Halbritter** (Spring Boot engineering team). This recording is the
  Devoxx CERN delivery (2026-02-10), a newer run than the earlier Devoxx Belgium one,
  uploaded a few weeks after the talk.

  A practical walkthrough of how to cut JVM startup ~4x today using only stock
  **JDK 25 + Spring Boot 4** — no preview flags, no GraalVM, no custom JDK. This is
  the technique our `jvm-aot` image implements. Summary:

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
    trade-off is the bean arrangement is frozen at build time. This is what the
    **`spring-aot`** image adds on top of `jvm-aot` (the `-Pspringaot` Maven profile runs
    `process-aot` at build time, and the image runs with `-Dspring.aot.enabled=true`).
  - **For warm-up (peak throughput), not just startup,** you need a *real* training run
    that exercises hot paths with production-like load — harder to set up than the poor
    man's run. **What's next** in the Leyden prototype: ahead-of-time *code* compilation
    (store compiled machine code in the cache → ~0.45s startup / ~5x, with
    portability/instruction-set trade-offs), AOT for user-defined classloaders (may
    remove the extract step), AOT object caching with any GC (JDK 26), and modular
    Spring AOT.
