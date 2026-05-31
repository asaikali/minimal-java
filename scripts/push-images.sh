#!/usr/bin/env bash
#
# Publish the chiseled-image series built by build-images.sh to a registry. This
# is the local/manual publish path; in CI the base-images.yml and containerize.yml
# workflows push these same images (and publish-artifact.sh / artifact.yml push
# the jar). Each image gets its own repository under the namespace:
# ghcr.io/<owner>/<repo>/<name> (e.g. .../minimal-java/jre).
#
# build-images.sh builds the series multi-arch and loads it into the local Docker
# image store as minimal-java/<name>:local. This script retags each of those local
# images to <registry-repo>/<name>:<tag> and pushes it. Pushing a multi-arch image
# straight from the local store requires the containerd image store — the same
# requirement build-images.sh has for its multi-arch --load.
#
# Build first, then push. With no argument the destination namespace defaults to
# ghcr.io/<owner>/<repo> derived from this repo's GitHub remote; pass a value to
# override (e.g. ghcr.io/you/minimal-java). The tag defaults to "latest".
#
#   build-images.sh       # build minimal-java/{ubuntu,jre,app,jvm-aot,spring-aot}:local
#   docker login ghcr.io  # or: gh auth token | docker login ghcr.io -u <you> --password-stdin
#   push-images.sh        # retag + push each -> ghcr.io/<owner>/<repo>/<name>:latest
#
# Usage:
#   push-images.sh [registry-repo] [tag]
#
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

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
  echo "usage: push-images.sh [registry-repo] [tag]" >&2
  echo "  with no arg, defaults to ghcr.io/<owner>/<repo> from the GitHub remote" >&2
  echo "  e.g. push-images.sh ghcr.io/you/minimal-java" >&2
  exit 1
fi

# Tag to publish under each per-image repository (defaults to latest).
TAG="${2:-latest}"

# Same series as build-images.sh, smallest first. The naive fat baseline is
# built locally for comparison but not published.
TARGETS=(ubuntu jre app jvm-aot spring-aot)

echo "Pushing minimal-java/*:local -> ${DEST}/*:${TAG}"

for target in "${TARGETS[@]}"; do
  src="minimal-java/${target}:local"
  dest="${DEST}/${target}:${TAG}"

  # The local image must exist — build-images.sh produces it. Fail with a clear
  # pointer rather than a raw "No such image" from docker tag.
  if ! docker image inspect "${src}" >/dev/null 2>&1; then
    echo "error: local image ${src} not found — run build-images.sh first." >&2
    exit 1
  fi

  echo
  echo ">>> ${dest}"
  docker tag "${src}" "${dest}"
  docker push "${dest}"
done
