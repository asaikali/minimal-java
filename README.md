# minimal-java

Experiments in building minimal, secure, and reproducible Java container runtimes.

A hands-on, teaching-oriented project that takes one ordinary Spring Boot app from a
naive container to a tiny, hardened, fast-starting one — **one question at a time**,
through a real CI/CD pipeline. The app is a typical Spring Boot 4 service (Java 25,
Spring MVC + Spring Data JPA / Hibernate over H2 with Flyway) that returns a random
quote. It's intentionally small so the focus stays on the **build-and-ship pipeline**,
not the app.

## Where it ends up

- **~2.5 MB base** — chiseled Ubuntu: no shell, no package manager, `libc6` only.
- **~119 MB for the whole app** — vs ~170 MB for the naive baseline.
- **~4.8× faster startup** — ~2.0 s → ~0.4 s via a JDK 25 AOT cache + Spring AOT.
- **Zero OS CVEs** on the chiseled images; remaining findings live in the app's jars.
- **Multi-arch** (`linux/amd64` + `linux/arm64`), **digest-pinned**, with an SBOM +
  SLSA provenance attestation on every image and the jar artifact.

The tutorial below earns each of those numbers step by step.

## The tutorial — three parts

Work through them in order; each builds on the last. Start at Part 1.

1. **[Part 1 — The pipeline & the naive fat jar](docs/1-pipeline.md)**
   Get the whole machine running with the simplest image: build the jar in CI, publish
   it as an OCI artifact with ORAS, containerize it (`fat`, on the full Temurin JRE),
   and publish to ghcr — *no* optimization yet. Ends on: **can we do better?**
2. **[Part 2 — A smaller, better-layered image](docs/2-size.md)**
   Make the *image* better: chiseled Ubuntu, a trimmed JRE, and the Spring Boot jar
   exploded into cache-friendly layers (`app`). Introduces the base-image pipeline and
   runtime hardening. The size and CVE win.
3. **[Part 3 — A faster app](docs/3-speed.md)**
   Make it *start* faster: the JDK 25 AOT cache (`jvm-aot`) and Spring AOT
   (`spring-aot`), the startup win, the AOT trade-offs, and deploying the result to
   Kubernetes.

## The image series at a glance

Six images. `fat` is the naive baseline; the other five build up bottom-up — a tiny
`ubuntu` base, a trimmed `jre`, then three packagings of the same app.

| Image                     | Builds on | Adds (the technique)                                     | Size (amd64) | Startup | Part |
| ------------------------- | --------- | -------------------------------------------------------- | ------------ | ------- | ---- |
| `ubuntu:26.04` (full)     | —         | the whole distro, for reference                          | ~42 MB       | —       | —    |
| `minimal-java/fat`        | full JRE  | the fat jar on the full Temurin JRE — **naive baseline** | ~170 MB      | ~2.0 s  | [1](docs/1-pipeline.md) |
| `minimal-java/ubuntu`     | `scratch` | Canonical **chisel** — package *slices*, no shell/apt    | ~2.5 MB      | —       | [2](docs/2-size.md) |
| `minimal-java/jre`        | `ubuntu`  | **trimmed Temurin JRE 25** — launchers removed           | ~65 MB       | —       | [2](docs/2-size.md) |
| `minimal-java/app`        | `jre`     | Spring Boot **layered jar**, exploded into cache layers  | ~119 MB      | ~1.6 s  | [2](docs/2-size.md) |
| `minimal-java/jvm-aot`    | `jre`     | a **JDK 25 AOT cache** (Project Leyden)                  | ~146 MB      | ~0.5 s  | [3](docs/3-speed.md) |
| `minimal-java/spring-aot` | `jre`     | the AOT cache **plus Spring AOT**                        | ~145 MB      | ~0.4 s  | [3](docs/3-speed.md) |

## How it's built

Each image has its own `Dockerfile` under [`images/`](images), wired into **three
decoupled pipelines** that hand off through a registry, every input pinned by digest —
the way a real platform/app team split the work:

```
  BASE IMAGES   images/2-size/{ubuntu,jre}  ──▶  ghcr base layer     (Part 2)
  ARTIFACT      mvn package + oras          ──▶  ghcr.io/…/jar        (Part 1)
  CONTAINERIZE  images/<group>/<name>       ──▶  ghcr.io/…/<name>     (each part)
```

Locally, [`scripts/build-images.sh`](scripts/build-images.sh) runs all three on one
machine (the daemon's image store is the hand-off instead of ghcr); in CI,
[`base-images.yml`](.github/workflows/base-images.yml),
[`artifact.yml`](.github/workflows/artifact.yml), and
[`containerize.yml`](.github/workflows/containerize.yml) publish to ghcr. Part 1 walks
through the pipeline in detail.

## Repository layout

The `images/` folders are grouped by the tutorial theme they teach, so the directory
order *is* the journey (`naive → size → speed`):

```
├── images/              the Dockerfiles, grouped by lesson  → images/README.md
│   ├── 1-naive/           fat                                (Part 1)
│   ├── 2-size/            ubuntu, jre, app                   (Part 2)
│   └── 3-speed/           jvm-aot, spring-aot                (Part 3)
├── src/  pom.xml  mvnw    the Spring Boot application (the constant across all images)
├── scripts/             build / publish / compare / run helpers  → scripts/README.md
├── k8s/                 sample hardened Kubernetes deployment     → k8s/README.md
├── docs/                the tutorial (1-pipeline, 2-size, 3-speed) + renovate
└── .github/workflows/   CI: the test gate + 3 pipelines + Renovate → workflows/README.md
```

Each directory has its own README. Image identity is independent of the folder: an
image keeps its bare name (`minimal-java/<name>:local`, `ghcr.io/<owner>/<repo>/<name>`)
regardless of which group folder its Dockerfile lives in.

## Reference

- **Dependency updates** — [Renovate](https://docs.renovatebot.com/) keeps the Maven
  deps, the base images / chisel release in the `images/**/Dockerfile` files, the Maven
  wrapper, and the GitHub Actions current. Setup and design notes:
  **[`docs/renovate.md`](docs/renovate.md)**.

  ```bash
  ./scripts/renovate.sh       # dry-run preview against the working tree (needs Node)
  ./scripts/run-renovate.sh   # dispatch the workflow now and tail its logs (needs gh)
  ```

- **Clean up** — remove everything the tutorial built locally:

  ```bash
  ./scripts/clean.sh
  ```
