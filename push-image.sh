#!/usr/bin/env bash
#
# Publish the chiseled-image series built by ./build-image.sh to a registry.
#
# build-image.sh builds the series multi-arch and loads it into the local Docker
# image store as minimal-java:<target>. This script retags each of those local
# images to a destination registry repository and pushes it. Pushing a multi-arch
# image straight from the local store requires the containerd image store — the
# same requirement build-image.sh has for its multi-arch --load.
#
# Build first, then push. With no argument the destination defaults to
# ghcr.io/<owner>/<repo> derived from this repo's GitHub remote; pass a value to
# override (e.g. ghcr.io/you/minimal-java).
#
#   ./build-image.sh      # build minimal-java:{ubuntu,jre,app,aot}
#   docker login ghcr.io  # or: gh auth token | docker login ghcr.io -u <you> --password-stdin
#   ./push-image.sh       # retag + push each -> ghcr.io/<owner>/<repo>
#
# Usage:
#   ./push-image.sh [registry-repo]
#
set -euo pipefail

cd "$(dirname "$0")"

# Destination registry repo. Defaults to ghcr.io/<owner>/<repo> derived from this
# repo's GitHub remote; an explicit argument overrides it.
DEST="${1:-}"
if [[ -z "${DEST}" ]]; then
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  if [[ "${url}" == *github.com* ]]; then
    DEST="ghcr.io/$(printf '%s' "${url}" | sed -E 's#^.*github\.com[:/]##; s#\.git$##' | tr '[:upper:]' '[:lower:]')"
  fi
fi
if [[ -z "${DEST}" ]]; then
  echo "usage: ./push-image.sh [registry-repo]" >&2
  echo "  with no arg, defaults to ghcr.io/<owner>/<repo> from the GitHub remote" >&2
  echo "  e.g. ./push-image.sh ghcr.io/you/minimal-java" >&2
  exit 1
fi

# Same series as build-image.sh, smallest first.
TARGETS=(ubuntu jre app aot)

echo "Pushing minimal-java:* -> ${DEST}:*"

for target in "${TARGETS[@]}"; do
  src="minimal-java:${target}"
  dest="${DEST}:${target}"

  # The local image must exist — build-image.sh produces it. Fail with a clear
  # pointer rather than a raw "No such image" from docker tag.
  if ! docker image inspect "${src}" >/dev/null 2>&1; then
    echo "error: local image ${src} not found — run ./build-image.sh first." >&2
    exit 1
  fi

  echo
  echo ">>> ${dest}"
  docker tag "${src}" "${dest}"
  docker push "${dest}"
done
