# 2-size — make it smaller

Three moves that shrink the image and drop the OS attack surface to zero, without
changing the app:

- **`golden-ubuntu/`** — a chiseled Ubuntu base built from `scratch` with Canonical's
  `chisel` (package *slices*, no shell, no package manager): ~2.5 MB.
- **`golden-jre/`** — the official Temurin JRE, trimmed of unused launchers, on the chiseled
  base. Built by the [base-images pipeline](../../.github/workflows/base-images.yml).
- **`app/`** — the Spring Boot jar **exploded into layers** (deps → loader → snapshot
  → application) for cache-friendly rebuilds, on the `golden-jre` base.

`golden-ubuntu` and `golden-jre` are *base* images (their own pipeline); `app` is a *runtime* image
(the containerize pipeline) — grouped here because they're the same lesson.

The **`golden-` prefix** marks them as the platform's owned, published base products that
everything else builds on. As such they **pin their upstream root by digest**
(`FROM ubuntu:…@sha256:…`, `FROM eclipse-temurin:…@sha256:…`) for reproducible builds,
with Renovate keeping the digests current — see [Part 2](../../docs/2-size.md) and
[`docs/renovate.md`](../../docs/renovate.md).

→ Explained in **[Part 2 — A smaller, better-layered image](../../docs/2-size.md)**.
