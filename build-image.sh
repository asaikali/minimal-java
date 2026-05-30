#!/usr/bin/env bash
#
# Build the chiseled-Ubuntu container image defined in ./Dockerfile.
#
# Builds a multi-arch (linux/amd64 + linux/arm64) image so it runs on both
# Apple Silicon Macs and amd64 Linux.
#
# Two workflows:
#
#   1. Local (default) — builds both arches and loads the manifest into the
#      local Docker so you can run it immediately. Requires the containerd
#      image store (Docker Desktop: Settings > General > "Use containerd for
#      pulling and storing images"); the legacy image store can't hold a
#      multi-arch manifest.
#
#        ./build-image.sh
#
#   2. Push — builds both arches and pushes the manifest to a registry, the
#      portable way to distribute a multi-arch image.
#
#        PUSH=true ./build-image.sh ghcr.io/you/minimal-java:chiseled
#
# Usage:
#   ./build-image.sh [IMAGE_TAG]
#
# Environment overrides:
#   PUSH             "true" -> push the manifest to a registry
#                    (default: false -> load into the local Docker)
#   PLATFORMS        comma-separated platforms
#                    (default: linux/amd64,linux/arm64)
#   CHISEL_VERSION   chisel release to download         (default: v1.4.1)
#   UBUNTU_VERSION   Ubuntu version (base + slices)     (default: 26.04)
#
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="${1:-minimal-java:chiseled}"
CHISEL_VERSION="${CHISEL_VERSION:-v1.4.1}"
UBUNTU_VERSION="${UBUNTU_VERSION:-26.04}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PUSH="${PUSH:-false}"
BUILDER="chisel-builder"

# Multi-platform builds and QEMU emulation need the docker-container driver;
# the default "docker" driver can't do either. Create the builder on demand.
if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
  echo "Creating buildx builder '${BUILDER}' (docker-container driver)..."
  docker buildx create --name "${BUILDER}" --driver docker-container --bootstrap >/dev/null
fi

build_args=(
  --builder "${BUILDER}"
  --build-arg "CHISEL_VERSION=${CHISEL_VERSION}"
  --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}"
  --tag "${IMAGE_TAG}"
)

echo "Building ${IMAGE_TAG}"
echo "  chisel:    ${CHISEL_VERSION}"
echo "  ubuntu:    ${UBUNTU_VERSION}"
echo "  platforms: ${PLATFORMS}"

build_args+=(--platform "${PLATFORMS}")

if [[ "${PUSH}" == "true" ]]; then
  echo "  output:    push to registry"
  docker buildx build "${build_args[@]}" --push .
  echo
  echo "Pushed ${IMAGE_TAG}"
else
  echo "  output:    load into local Docker"
  docker buildx build "${build_args[@]}" --load .
  echo
  echo "Built ${IMAGE_TAG}"

  # Pull the full Ubuntu base image for the same platforms so we can show a
  # like-for-like (uncompressed disk usage) size comparison against the
  # chiseled result.
  echo
  echo "Base image (for comparison):"
  IFS=',' read -ra _platforms <<< "${PLATFORMS}"
  for _p in "${_platforms[@]}"; do
    docker pull --quiet --platform "${_p}" "ubuntu:${UBUNTU_VERSION}" >/dev/null
  done
  # --tree prints per-architecture sizes in MB (no manual formatting needed).
  docker image ls --tree "ubuntu:${UBUNTU_VERSION}"

  echo
  echo "Chiseled image:"
  docker image ls --tree "${IMAGE_TAG}"
fi
