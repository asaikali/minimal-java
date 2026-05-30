#!/usr/bin/env bash
#
# Build the series of chiseled-Ubuntu images defined in ./Dockerfile, one per
# Dockerfile target, each progressively richer:
#
#   ubuntu — chiseled Ubuntu (base-files + libc6) only
#   jre    — chiseled ubuntu + a trimmed Eclipse Temurin JRE 25
#   app    — jre + the Spring Boot app, exploded into Spring Boot layers
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
#   CHISEL_VERSION   chisel release to download         (default: v1.4.1)
#   UBUNTU_VERSION   Ubuntu version (base + slices)     (default: 26.04)
#
set -euo pipefail

cd "$(dirname "$0")"

REPO="${1:-minimal-java}"
CHISEL_VERSION="${CHISEL_VERSION:-v1.4.1}"
UBUNTU_VERSION="${UBUNTU_VERSION:-26.04}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PUSH="${PUSH:-false}"
BUILDER="chisel-builder"

# Dockerfile targets to build, in series order (smallest first).
TARGETS=(ubuntu jre app)

# Multi-platform builds and QEMU emulation need the docker-container driver;
# the default "docker" driver can't do either. Create the builder on demand.
if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
  echo "Creating buildx builder '${BUILDER}' (docker-container driver)..."
  docker buildx create --name "${BUILDER}" --driver docker-container --bootstrap >/dev/null
fi

# Shared buildx args; per-target --target/--tag are appended in the loop below.
common_args=(
  --builder "${BUILDER}"
  --build-arg "CHISEL_VERSION=${CHISEL_VERSION}"
  --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}"
  --platform "${PLATFORMS}"
)

echo "Building ${REPO} series: ${TARGETS[*]}"
echo "  chisel:    ${CHISEL_VERSION}"
echo "  ubuntu:    ${UBUNTU_VERSION}"
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
# on push (the images aren't in the local store to inspect).
if [[ "${PUSH}" != "true" ]]; then
  # Pull the full Ubuntu base image for the same platforms so we can show a
  # like-for-like (uncompressed disk usage) comparison against the chiseled
  # results.
  IFS=',' read -ra _platforms <<< "${PLATFORMS}"
  for _p in "${_platforms[@]}"; do
    docker pull --quiet --platform "${_p}" "ubuntu:${UBUNTU_VERSION}" >/dev/null
  done

  echo
  echo "Size comparison (ubuntu base -> chiseled series):"
  echo
  # --tree prints per-architecture sizes in MB (no manual formatting needed).
  docker image ls --tree "ubuntu:${UBUNTU_VERSION}"
  for target in "${TARGETS[@]}"; do
    echo
    docker image ls --tree "${REPO}:${target}"
  done
fi
