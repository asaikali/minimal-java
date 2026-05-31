# Part 1 — The pipeline & the naive fat jar

> **minimal-java tutorial** · **Part 1** · [Part 2 — a smaller image →](2-layering.md) · [Part 3 — a faster app →](3-speed.md) · [↑ Overview](../README.md)

Before optimizing anything, get the whole machine running end to end with the
**simplest possible image**. This part builds a Spring Boot app into a container and
publishes it through a real, decoupled pipeline — *no* chisel, *no* layering, *no*
AOT. Once that's familiar, Parts 2 and 3 make the image smaller, safer, and faster.

The starting image is **`fat`**: the Spring Boot fat jar on the **full** Eclipse
Temurin JRE. It's what most people write by hand — and exactly the baseline we'll
improve from.

## Before you start

- **Required** — Docker with the **containerd image store** enabled (Docker Desktop:
  *Settings → General → "Use containerd for pulling and storing images"*). It's what
  lets a multi-arch image load into your local store; the legacy store can't hold one.
- **Optional, used later** — `trivy` + `jq` (Part 2's CVE step) and `kubectl` pointed at
  Docker Desktop's cluster (Part 3's deploy step). You don't need them here.

## The application

A typical Spring Boot 4 service: Java 25, Spring MVC exposing a REST API, backed by
Spring Data JPA / Hibernate over an H2 database with Flyway migrations. It has one
endpoint that returns a random quote. It's intentionally small so the focus stays on
the **build-and-ship pipeline**, not the app.

## The pipeline, in three stages

A naive setup builds everything from one big multi-stage `Dockerfile`. This repo
splits the work the way real teams do — into stages that **hand off through a
registry**, each input pinned by **digest**:

```
  BUILD THE JAR        mvn package  ──▶  application.jar
  PUBLISH THE ARTIFACT oras push    ──▶  ghcr.io/<owner>/<repo>/jar:<ver>   (the jar as an OCI artifact)
                                                  │ oras pull
                                                  ▼
  CONTAINERIZE         images/fat   ──▶  ghcr.io/<owner>/<repo>/fat        (FROM the full Temurin JRE)
```

Notice what's *not* here yet: there's no custom base image — `fat` builds `FROM` the
upstream `eclipse-temurin` JRE. We introduce a base-image pipeline in
[Part 2](2-layering.md), once we want something smaller than the full JRE.

### Stage 1 — build the jar

The application is compiled and tested by [`build.yml`](../.github/workflows/build.yml),
the fast CI gate (`./mvnw -B verify` — compile, run the tests, package the jar). A
green check there is the signal an upgrade is safe; it builds *only* the jar, no
images, so ordinary PRs stay quick.

### Stage 2 — publish the jar as an OCI artifact

The jar is **architecture-independent**, so it's built **once** and published as a
first-class OCI **artifact** with [ORAS](https://oras.land) — *not* as a container
image — by [`publish-artifact.sh`](../scripts/publish-artifact.sh) (in CI,
[`artifact.yml`](../.github/workflows/artifact.yml)):

```bash
oras push ghcr.io/<owner>/<repo>/jar:<ver> application.jar
```

Putting the jar in the registry makes it the **single source of truth**: it carries
its own version/provenance, and any number of packaging pipelines pull that exact
artifact instead of recompiling. (Two jars are actually published — a plain one and a
Spring-AOT one for [Part 3](3-speed.md); `fat` uses the plain one.)

### Stage 3 — containerize

[`images/fat/Dockerfile`](../images/fat) is the whole "package it" step — and it's tiny:

```dockerfile
FROM eclipse-temurin:25-jre
WORKDIR /app
COPY application.jar application.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "application.jar"]
```

The pipeline ([`containerize.yml`](../.github/workflows/containerize.yml)) `oras pull`s
the jar into the build context, so the Dockerfile just `COPY`s `application.jar` — no
compilation happens here. The result is published to `ghcr.io/<owner>/<repo>/fat` with
an SBOM + SLSA provenance attestation.

## Do it locally

[`build-images.sh`](../scripts/build-images.sh) runs the whole pipeline on one machine
(it builds the entire series — we'll focus on `fat` here):

```bash
./scripts/build-images.sh
```

Locally the hand-off is the daemon's image store rather than ghcr, and the jar is fed
from a small `stage/` context instead of `oras pull` — but the Dockerfiles and the
flow are identical to CI.

Run the `fat` image and call the API:

```bash
./scripts/run-fat.sh
```

```bash
$ curl localhost:8080
{"author":"Lord Herbert","id":5,"quote":"The shortest answer is doing"}
$ curl localhost:8080
{"author":"Vincent Lombardi","id":4,"quote":"Success demands singleness of purpose"}
```

A full Spring Boot 4 + JPA + Flyway + H2 service, packaged and answering requests.

## Publish + inspect the supply chain

In CI the pipelines publish to ghcr automatically. To do it from your machine and see
the attestations (which travel with the artifact in a registry, not on a local image):

```bash
gh auth token | docker login ghcr.io -u <you> --password-stdin
gh auth token | oras login   ghcr.io -u <you> --password-stdin
./scripts/publish-artifact.sh         # build + oras-push the jar  -> ghcr.io/<owner>/<repo>/jar
./scripts/push-images.sh              # push the images            -> ghcr.io/<owner>/<repo>/<name>
./scripts/inspect-attestations.sh     # show the jar + each image's SBOM + provenance
```

With no argument these derive `ghcr.io/<owner>/<repo>` from your git remote.

## Where we are — and the catch

You now have a working, published, attested pipeline. But `fat` is the *naive*
baseline:

- It's **~170 MB** — it carries the **full** Temurin JRE plus the whole OS that JRE
  image ships on (a shell, a package manager, dozens of OS packages).
- It runs the **nested-jar fat jar**, the slowest way to start (~2 s — measured in
  [Part 3](3-speed.md)).
- It runs as **root**, and `run-fat.sh` runs it with no hardening at all.

So: **can we do better?** Can the image be dramatically smaller and carry far fewer
CVEs, without changing the app? That's [Part 2](2-layering.md).

---

> **Next:** [Part 2 — a smaller, better-layered image →](2-layering.md)
