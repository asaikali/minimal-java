#!/usr/bin/env bash
#
# Build the application artifact ONCE and publish it to an OCI registry with
# ORAS (https://oras.land), so the containerize pipelines can pull that exact
# jar instead of recompiling. This is the "build the software" half of the
# decoupled pipeline; images/{fat,app,jvm-aot,spring-aot} are the "package it"
# half (they oras-pull what this produces). The jar is architecture-independent,
# so it's built once here and reused by every per-arch image.
#
# Two jars are produced and published as SEPARATE artifacts, because Spring AOT
# needs its own build (-Pspringaot):
#   <repo>/jar:<ver>             the plain jar      (feeds fat, app, jvm-aot)
#   <repo>/jar:<ver>-springaot   the Spring-AOT jar (feeds spring-aot)
# Each also gets a moving latest / latest-springaot tag for convenience.
#
# Both jars are always staged locally under ./stage/{plain,springaot}/application.jar
# so build-images.sh can consume them directly for an offline local build.
#
# Usage:
#   publish-artifact.sh --local              # build + stage only, no push (default for local builds)
#   publish-artifact.sh [registry-repo]      # build, stage, and oras-push to the registry
#
# With no registry-repo the destination defaults to ghcr.io/<owner>/<repo>
# derived from this repo's GitHub remote (same default as push-images.sh).
# Pushing assumes you're already authenticated, e.g.:
#   gh auth token | oras login ghcr.io -u <you> --password-stdin
#
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Media type advertised for the jar artifact so registries/tools can tell what
# the blob is (ORAS records it as the manifest's artifactType).
ARTIFACT_TYPE="application/vnd.minimal-java.jar+jar"

LOCAL=0
DEST="${1:-}"
if [[ "${DEST}" == "--local" ]]; then
  LOCAL=1
  DEST=""
fi

# Destination registry repo (only needed when pushing). Defaults to
# ghcr.io/<owner>/<repo> from the GitHub remote; an explicit argument overrides.
if [[ "${LOCAL}" -eq 0 && -z "${DEST}" ]]; then
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  if [[ "${url}" == *github.com* ]]; then
    DEST="ghcr.io/$(printf '%s' "${url}" | sed -E 's#^.*github\.com[:/]##; s#\.git$##' | tr '[:upper:]' '[:lower:]')"
  fi
  if [[ -z "${DEST}" ]]; then
    echo "usage: publish-artifact.sh [--local] [registry-repo]" >&2
    echo "  with no arg, defaults to ghcr.io/<owner>/<repo> from the GitHub remote" >&2
    exit 1
  fi
fi

# Immutable version tag for this build: project version + short commit SHA. The
# project's own <version> is the first one after </parent> (the <parent> block
# has its own <version>, which appears earlier in the file).
PROJECT_VERSION="$(awk '/<\/parent>/{p=1} p&&/<version>/{gsub(/.*<version>|<\/version>.*/,""); print; exit}' pom.xml)"
SHA="$(git rev-parse --short HEAD)"
VERSION="${PROJECT_VERSION:-0}-${SHA}"

# Build one variant and stage its jar under stage/<name>/application.jar.
#   $1 = stage name (plain|springaot)   $2... = extra mvn args
stage_jar() {
  local name="$1"; shift
  echo
  echo ">>> building ${name} jar (./mvnw -B -DskipTests package $*)"
  ./mvnw -B -DskipTests "$@" package
  mkdir -p "stage/${name}"
  cp target/*.jar "stage/${name}/application.jar"
}

rm -rf stage
stage_jar plain
stage_jar springaot -Pspringaot

if [[ "${LOCAL}" -eq 1 ]]; then
  echo
  echo "Staged (local, not pushed):"
  echo "  stage/plain/application.jar"
  echo "  stage/springaot/application.jar"
  exit 0
fi

ARTIFACT="${DEST}/jar"

# Push one staged jar as an OCI artifact, then add a moving tag. Run from inside
# the stage dir so the artifact stores the file as a clean "application.jar".
#   $1 = stage dir name   $2 = immutable tag   $3 = moving tag
push_jar() {
  local name="$1" tag="$2" moving="$3"
  echo
  echo ">>> ${ARTIFACT}:${tag}"
  ( cd "stage/${name}" && oras push "${ARTIFACT}:${tag}" \
      --artifact-type "${ARTIFACT_TYPE}" \
      application.jar )
  oras tag "${ARTIFACT}:${tag}" "${moving}"
}

push_jar plain     "${VERSION}"            latest
push_jar springaot "${VERSION}-springaot"  latest-springaot

echo
echo "Published:"
echo "  ${ARTIFACT}:${VERSION}            (also tagged latest)"
echo "  ${ARTIFACT}:${VERSION}-springaot  (also tagged latest-springaot)"
