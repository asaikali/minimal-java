# 2-size — make it smaller

Three moves that shrink the image and drop the OS attack surface to zero, without
changing the app:

- **`ubuntu/`** — a chiseled Ubuntu base built from `scratch` with Canonical's
  `chisel` (package *slices*, no shell, no package manager): ~2.5 MB.
- **`jre/`** — the official Temurin JRE, trimmed of unused launchers, on the chiseled
  base. Built by the [base-images pipeline](../../.github/workflows/base-images.yml).
- **`app/`** — the Spring Boot jar **exploded into layers** (deps → loader → snapshot
  → application) for cache-friendly rebuilds, on the `jre` base.

`ubuntu` and `jre` are *base* images (their own pipeline); `app` is a *runtime* image
(the containerize pipeline) — grouped here because they're the same lesson.

→ Explained in **[Part 2 — A smaller, better-layered image](../../docs/2-size.md)**.
