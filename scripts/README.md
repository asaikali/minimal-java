# scripts/

Helper scripts for building, publishing, comparing, and running the image series.
They're plain bash and run by path from the repo root (`./scripts/<name>.sh`); with
[mise](https://mise.jdx.dev) active they also run as bare commands (`mise.toml` adds
`scripts/` to `PATH`).

Grouped by purpose:

### Build
- **`build-images.sh`** — build the whole series locally (base → jar → runtime),
  multi-arch, and print the size table. The main entry point.
- **`publish-artifact.sh`** — build the jar(s) and publish them as an OCI artifact via
  ORAS (`--local` just stages them for `build-images.sh`).

### Publish
- **`push-images.sh`** — retag the local images and push them to ghcr.
- **`inspect-attestations.sh`** — show the SBOM + provenance attestations on the
  published images and jar.

### Compare (the tutorial's measurements)
- **`image-sizes.sh`** — per-arch size table across all images.
- **`cve-counts.sh`** — Trivy CVE counts per image (needs `trivy` + `jq`).
- **`startup-times.sh`** — Spring Boot startup time for fat / app / jvm-aot / spring-aot.

### Run
- **`run-fat.sh`** — run the naive `fat` image, plain (no hardening).
- **`run-app.sh`**, **`run-jvm-aot.sh`**, **`run-spring-aot.sh`** — run the chiseled
  images **hardened** (non-root, read-only rootfs, caps dropped).

### Maintain
- **`clean.sh`** — remove the local images, leftover containers, and staged jars.

### Renovate
- **`renovate.sh`** — dry-run preview of what Renovate would propose (needs Node).
- **`run-renovate.sh`** — dispatch the Renovate workflow and tail its logs (needs `gh`).
  See [`docs/renovate.md`](../docs/renovate.md).
