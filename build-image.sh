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
# Builds both arches and loads each manifest into the local Docker store so you
# can run them immediately. Loading a multi-arch manifest requires the containerd
# image store (Docker Desktop: Settings > General > "Use containerd for pulling
# and storing images"); the legacy image store can't hold one.
#
#   ./build-image.sh           # build minimal-java:{ubuntu,jre,app,aot}
#   ./build-image.sh myrepo    # tag the series myrepo:<target> instead
#
# To publish the built series to a registry, build first, then ./push-image.sh.
#
# Usage:
#   ./build-image.sh [REPO]
#
# Environment overrides:
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
echo "  output:    load into local Docker"

for target in "${TARGETS[@]}"; do
  tag="${REPO}:${target}"
  echo
  echo ">>> ${tag} (--target ${target})"
  # The jre target's jlink stage runs emulated for the non-native arch, so its
  # first build is noticeably slower than base.
  docker buildx build "${common_args[@]}" --target "${target}" --tag "${tag}" --load .
done

# Size comparison: full Ubuntu base vs each chiseled image, side by side.
# Delegated to image-stats.sh, which is also runnable on its own to re-check
# sizes later.
echo
PLATFORMS="${PLATFORMS}" ./image-stats.sh "${REPO}"
