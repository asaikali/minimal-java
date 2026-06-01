#!/usr/bin/env bash
#
# Show the SBOM + SLSA provenance attestations attached to each published image
# and to the jar artifact. Attestations travel with the artifact in a registry,
# so inspect a copy pushed by push-images.sh / publish-artifact.sh (they aren't
# visible on a local-only image):
#
#   build-images.sh            # build (attaches the image attestations)
#   push-images.sh             # push the images to the registry
#   publish-artifact.sh        # push the jar artifact to the registry
#   inspect-attestations.sh   # inspect them there
#
# Covers the base images (ubuntu, jre), the runtime images (app, jvm-aot,
# spring-aot), and the jar OCI artifact. With no argument the namespace defaults
# to ghcr.io/<owner>/<repo> derived from this repo's GitHub remote (same default
# as push-images.sh); pass a value to override.
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
#   inspect-attestations.sh [registry-repo]
#
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Registry repo to inspect. Defaults to ghcr.io/<owner>/<repo> derived from this
# repo's GitHub remote; an explicit argument overrides it.
DEST="${1:-}"
if [[ -z "${DEST}" ]]; then
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  if [[ "${url}" == *github.com* ]]; then
    DEST="ghcr.io/$(printf '%s' "${url}" | sed -E 's#^.*github\.com[:/]##; s#\.git$##' | tr '[:upper:]' '[:lower:]')"
  fi
fi
if [[ -z "${DEST}" ]]; then
  echo "usage: inspect-attestations.sh [registry-repo]" >&2
  echo "  with no arg, defaults to ghcr.io/<owner>/<repo> from the GitHub remote" >&2
  echo "  e.g. inspect-attestations.sh ghcr.io/you/minimal-java" >&2
  exit 1
fi

# Same series push-images.sh publishes, plus the jar OCI artifact
# publish-artifact.sh pushes.
REFS=(
  "${DEST}/golden-ubuntu:latest"
  "${DEST}/golden-jre:latest"
  "${DEST}/fat:latest"
  "${DEST}/app:latest"
  "${DEST}/jvm-aot:latest"
  "${DEST}/spring-aot:latest"
  "${DEST}/jar:latest"
  "${DEST}/jar:latest-springaot"
)

# Bold the ">>> <ref>" headers on a terminal; plain when piped.
if [[ -t 1 ]]; then bold=$'\e[1m'; reset=$'\e[0m'; else bold=""; reset=""; fi

for ref in "${REFS[@]}"; do
  echo
  echo "${bold}>>> ${ref}${reset}"
  docker buildx imagetools inspect "${ref}"
done
