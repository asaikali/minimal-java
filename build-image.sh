#!/usr/bin/env bash
#
# Build the chiseled-Ubuntu container image defined in ./Dockerfile.
#
# Two workflows:
#
#   1. Local (default) — builds for your host architecture and loads the image
#      into the local Docker so you can run it immediately (e.g. on an Apple
#      Silicon Mac it builds linux/arm64; on an amd64 Linux box, linux/amd64).
#
#        ./build-image.sh
#
#   2. Multi-arch — builds linux/amd64 + linux/arm64 as a single manifest and
#      pushes it to a registry. Docker cannot load a multi-arch manifest into
#      the local image store, so this path requires pushing. The pushed image
#      then runs on both Mac (arm64) and Linux (amd64).
#
#        PUSH=true ./build-image.sh ghcr.io/you/minimal-java:chiseled
#
# Usage:
#   ./build-image.sh [IMAGE_TAG]
#
# Environment overrides:
#   PUSH             "true" -> multi-arch build pushed to a registry
#                    (default: false -> single-arch build loaded locally)
#   PLATFORMS        comma-separated platforms
#                    (default: host arch when loading; amd64,arm64 when pushing)
#   CHISEL_VERSION   chisel release to download         (default: v1.4.1)
#   UBUNTU_VERSION   Ubuntu version (base + slices)     (default: 26.04)
#
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="${1:-minimal-java:chiseled}"
CHISEL_VERSION="${CHISEL_VERSION:-v1.4.1}"
UBUNTU_VERSION="${UBUNTU_VERSION:-26.04}"
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
echo "  chisel: ${CHISEL_VERSION}"
echo "  ubuntu: ${UBUNTU_VERSION}"

if [[ "${PUSH}" == "true" ]]; then
  PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
  echo "  platforms: ${PLATFORMS} (multi-arch, pushing to registry)"
  docker buildx build "${build_args[@]}" --platform "${PLATFORMS}" --push .
  echo
  echo "Pushed ${IMAGE_TAG}"
else
  # Single-arch so the result can be loaded into the local Docker and run.
  if [[ -n "${PLATFORMS:-}" ]]; then
    build_args+=(--platform "${PLATFORMS}")
    echo "  platform: ${PLATFORMS} (loaded locally)"
  else
    echo "  platform: host (loaded locally)"
  fi
  docker buildx build "${build_args[@]}" --load .
  echo
  echo "Built ${IMAGE_TAG}"
  docker image inspect "${IMAGE_TAG}" --format 'Size: {{.Size}} bytes'
fi
