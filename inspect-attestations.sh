#!/usr/bin/env bash
#
# Show the SBOM + SLSA provenance attestations that build-image.sh attached to
# each image. Attestations travel with the image in a registry, so inspect a
# copy pushed by ./push-image.sh (they aren't visible on a local-only image):
#
#   ./build-image.sh                            # build (attaches the attestations)
#   ./push-image.sh ghcr.io/you/minimal-java    # push them to the registry
#   ./inspect-attestations.sh ghcr.io/you/minimal-java
#
# For each tag this prints `docker buildx imagetools inspect`, whose manifest
# list shows the per-platform images alongside their attestation manifests
# (vnd.docker.reference.type=attestation-manifest). To dump the full data, add a
# format, e.g.:
#
#   docker buildx imagetools inspect <ref> --format '{{ json .Provenance }}'
#   docker buildx imagetools inspect <ref> --format '{{ json .SBOM }}'
#
# Usage:
#   ./inspect-attestations.sh <registry-repo>
#
set -euo pipefail

cd "$(dirname "$0")"

DEST="${1:-}"

if [[ -z "${DEST}" ]]; then
  echo "usage: ./inspect-attestations.sh <registry-repo>" >&2
  echo "  e.g. ./inspect-attestations.sh ghcr.io/you/minimal-java" >&2
  exit 1
fi

# Same series push-image.sh publishes (the naive fat baseline isn't published).
TARGETS=(ubuntu jre app aot)

# Bold the ">>> <ref>" headers on a terminal; plain when piped.
if [[ -t 1 ]]; then bold=$'\e[1m'; reset=$'\e[0m'; else bold=""; reset=""; fi

for target in "${TARGETS[@]}"; do
  ref="${DEST}:${target}"
  echo
  echo "${bold}>>> ${ref}${reset}"
  docker buildx imagetools inspect "${ref}"
done
