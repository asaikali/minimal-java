#!/usr/bin/env bash
#
# Publish the chiseled-image series built by ./build-image.sh to a registry.
#
# build-image.sh builds the series multi-arch and loads it into the local Docker
# image store as <local-repo>:<target> (default repo: minimal-java). This script
# retags each of those local images to a destination registry repository and
# pushes it. Pushing a multi-arch image straight from the local store requires
# the containerd image store — the same requirement build-image.sh has for its
# multi-arch --load.
#
# Build first, then push:
#
#   ./build-image.sh                          # build minimal-java:{ubuntu,jre,app,aot}
#   docker login ghcr.io                      # authenticate to the target registry
#   ./push-image.sh ghcr.io/you/minimal-java  # retag + push each to that repo
#
# Usage:
#   ./push-image.sh <registry-repo> [<local-repo>]
#
#   <registry-repo>  destination, e.g. ghcr.io/you/minimal-java (required)
#   <local-repo>     locally-built repo to push from   (default: minimal-java)
#
set -euo pipefail

cd "$(dirname "$0")"

DEST="${1:-}"
SRC="${2:-minimal-java}"

if [[ -z "${DEST}" ]]; then
  echo "usage: ./push-image.sh <registry-repo> [<local-repo>]" >&2
  echo "  e.g. ./push-image.sh ghcr.io/you/minimal-java" >&2
  exit 1
fi

# Same series as build-image.sh, smallest first.
TARGETS=(ubuntu jre app aot)

echo "Pushing ${SRC}:* -> ${DEST}:*"

for target in "${TARGETS[@]}"; do
  src="${SRC}:${target}"
  dest="${DEST}:${target}"

  # The local image must exist — build-image.sh produces it. Fail with a clear
  # pointer rather than a raw "No such image" from docker tag.
  if ! docker image inspect "${src}" >/dev/null 2>&1; then
    echo "error: local image ${src} not found — run ./build-image.sh first (repo '${SRC}')." >&2
    exit 1
  fi

  echo
  echo ">>> ${dest}"
  docker tag "${src}" "${dest}"
  docker push "${dest}"
done
