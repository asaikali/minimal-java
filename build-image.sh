#!/usr/bin/env bash
#
# Build the series of chiseled-Ubuntu images defined in ./Dockerfile, one per
# Dockerfile target, each progressively richer:
#
#   ubuntu — chiseled Ubuntu (base-files + libc6) only
#   jre    — chiseled ubuntu + a trimmed Eclipse Temurin JRE 25
#   app    — jre + the Spring Boot app, exploded into Spring Boot layers
#   aot    — app + a JDK 25 AOT cache (training run) for faster startup
#
# Each is built multi-arch (linux/amd64 + linux/arm64) so it runs on both
# Apple Silicon Macs and amd64 Linux, and tagged ${REPO}:<target>.
#
# Two workflows:
#
#   1. Local (default) — builds both arches and loads each manifest into the
#      local Docker so you can run them immediately. Requires the containerd
#      image store (Docker Desktop: Settings > General > "Use containerd for
#      pulling and storing images"); the legacy image store can't hold a
#      multi-arch manifest.
#
#        ./build-image.sh
#
#   2. Push — builds both arches and pushes each manifest to a registry, the
#      portable way to distribute a multi-arch image.
#
#        PUSH=true ./build-image.sh ghcr.io/you/minimal-java
#
# Usage:
#   ./build-image.sh [REPO]
#
# Environment overrides:
#   PUSH             "true" -> push the manifests to a registry
#                    (default: false -> load into the local Docker)
#   PLATFORMS        comma-separated platforms
#                    (default: linux/amd64,linux/arm64)
#
# Image versions (Ubuntu, JRE, chisel) are NOT set here — they live in the
# Dockerfile's ARG lines, the single source of truth. To change one, edit the
# Dockerfile (which is also what Renovate updates).
#
set -euo pipefail

cd "$(dirname "$0")"

REPO="${1:-minimal-java}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PUSH="${PUSH:-false}"
BUILDER="chisel-builder"

# Dockerfile targets to build, in series order (smallest first).
TARGETS=(ubuntu jre app aot)

# Multi-platform builds and QEMU emulation need the docker-container driver;
# the default "docker" driver can't do either. Create the builder on demand.
if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
  echo "Creating buildx builder '${BUILDER}' (docker-container driver)..."
  docker buildx create --name "${BUILDER}" --driver docker-container --bootstrap >/dev/null
fi

# Shared buildx args; per-target --target/--tag are appended in the loop below.
common_args=(
  --builder "${BUILDER}"
  --platform "${PLATFORMS}"
)

echo "Building ${REPO} series: ${TARGETS[*]}"
echo "  platforms: ${PLATFORMS}"

if [[ "${PUSH}" == "true" ]]; then
  echo "  output:    push to registry"
else
  echo "  output:    load into local Docker"
fi

for target in "${TARGETS[@]}"; do
  tag="${REPO}:${target}"
  echo
  echo ">>> ${tag} (--target ${target})"
  # The jre target's jlink stage runs emulated for the non-native arch, so its
  # first build is noticeably slower than base.
  if [[ "${PUSH}" == "true" ]]; then
    docker buildx build "${common_args[@]}" --target "${target}" --tag "${tag}" --push .
  else
    docker buildx build "${common_args[@]}" --target "${target}" --tag "${tag}" --load .
  fi
done

# Size comparison: full Ubuntu base vs each chiseled image, side by side. Skip
# on push (the images aren't in the local store to inspect). Delegated to
# image-stats.sh, which is also runnable on its own to re-check sizes later.
if [[ "${PUSH}" != "true" ]]; then
  echo
  PLATFORMS="${PLATFORMS}" ./image-stats.sh "${REPO}"
fi
