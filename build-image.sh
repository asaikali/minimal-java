#!/usr/bin/env bash
#
# Build the chiseled-Ubuntu container image defined in ./Dockerfile.
#
# Usage:
#   ./build-image.sh [IMAGE_TAG]
#
# Environment overrides:
#   CHISEL_VERSION   chisel release to download         (default: v1.4.1)
#   UBUNTU_VERSION   Ubuntu version (base + slices)     (default: 26.04)
#   PLATFORM         target platform for buildx         (default: host platform)
#
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="${1:-minimal-java:chiseled}"
CHISEL_VERSION="${CHISEL_VERSION:-v1.4.1}"
UBUNTU_VERSION="${UBUNTU_VERSION:-26.04}"

echo "Building ${IMAGE_TAG}"
echo "  chisel: ${CHISEL_VERSION}"
echo "  ubuntu: ${UBUNTU_VERSION}"

build_args=(
  --build-arg "CHISEL_VERSION=${CHISEL_VERSION}"
  --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}"
  --tag "${IMAGE_TAG}"
)

if [[ -n "${PLATFORM:-}" ]]; then
  build_args+=(--platform "${PLATFORM}")
fi

docker build "${build_args[@]}" .

echo
echo "Built ${IMAGE_TAG}"
docker image inspect "${IMAGE_TAG}" --format 'Size: {{.Size}} bytes'
