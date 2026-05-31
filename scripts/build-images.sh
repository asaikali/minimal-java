#!/usr/bin/env bash
#
# Build the whole decoupled image series locally, end to end, so the compare
# scripts (image-sizes.sh, cve-counts.sh, startup-times.sh) have everything to
# work with. This drives the same three stages CI runs as separate pipelines,
# but wired together on one machine:
#
#   base images      images/ubuntu  -> minimal-java/ubuntu:local
#                    images/jre     -> minimal-java/jre:local   (FROM the ubuntu base)
#   artifact         mvn package x2 -> stage/{plain,springaot}/application.jar
#   runtime images   images/fat        (full JRE + the plain jar — naive baseline)
#                    images/app        (jre base + exploded plain jar)
#                    images/jvm-aot     (app + JDK AOT cache)
#                    images/spring-aot  (Spring-AOT jar + JDK AOT cache)
#
# In CI the registry (ghcr.io) is the hand-off point between these stages, with
# everything pinned by digest. Locally the hand-off is the daemon's image store:
# each runtime image is built FROM the jre base's local tag, and the jar arrives
# pre-built in a tiny build context (stage/<variant>/) instead of via `oras pull`.
#
# Each image is built multi-arch (linux/amd64 + linux/arm64) and loaded into the
# local store so you can run either arch immediately. Override the set with e.g.
# `PLATFORMS=linux/arm64 ./scripts/build-images.sh` for a faster native-only build.
#
# Requirements (Docker Desktop's defaults satisfy both):
#   - the containerd image store, to --load a multi-arch manifest
#     (Settings > General > "Use containerd for pulling and storing images");
#   - QEMU/binfmt, so the non-native arch's RUN steps (the JRE trim and the AOT
#     training runs) can execute under emulation.
#
# Versions (Ubuntu, JRE, chisel) are NOT set here — they live in the per-image
# Dockerfiles' ARG lines, the single source of truth Renovate updates.
#
# To publish to a registry, see scripts/publish-artifact.sh (the jar) and
# scripts/push-images.sh (the images), or the CI workflows under .github/.
#
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

NS="minimal-java"           # local image namespace: minimal-java/<name>:local
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# Use the docker-driver buildx builder bound to the current context (its name IS
# the context name). Unlike a docker-container builder, the docker driver reads
# the local image store, so each image can be built FROM the previous one's
# :local tag — the cross-image hand-off the decoupled series depends on. With the
# containerd image store it still builds multi-arch and --loads.
BUILDER="$(docker context show 2>/dev/null || echo default)"

# --sbom/--provenance attach a Software Bill of Materials and SLSA build
# provenance to each image; they travel with it when pushed, where
# `docker buildx imagetools inspect <ref>` can show them (not on a local image).
build() {  # $1 = image name, $2 = build context dir, rest = extra build args
  local name="$1" context="$2"; shift 2
  echo
  echo ">>> ${NS}/${name}:local"
  docker buildx build \
    --builder "${BUILDER}" \
    --platform "${PLATFORMS}" \
    --sbom=true --provenance=mode=max \
    -f "images/${name}/Dockerfile" \
    "$@" \
    --tag "${NS}/${name}:local" --load "${context}"
}

# 1. Base images. The jre build runs a RUN step (trimming the JRE launchers) that
#    executes emulated for the non-native arch, so it's slower than ubuntu. jre is
#    built FROM the ubuntu base's local tag.
build ubuntu images/ubuntu
build jre    images/jre --build-arg "UBUNTU_BASE=${NS}/ubuntu:local"

# 2. Artifact. Build the plain + Spring-AOT jars once and stage them under
#    stage/{plain,springaot}/application.jar (the runtime builds' contexts).
"$(dirname "$0")/publish-artifact.sh" --local

# 3. Runtime images, each FROM the jre base, consuming a staged jar as context.
#    fat is the naive baseline (full Temurin JRE, plain jar, no techniques).
build fat        stage/plain
build app        stage/plain     --build-arg "JRE_BASE=${NS}/jre:local"
build jvm-aot    stage/plain     --build-arg "JRE_BASE=${NS}/jre:local"
build spring-aot stage/springaot --build-arg "JRE_BASE=${NS}/jre:local"

# Size comparison: full Ubuntu base vs each chiseled image, side by side.
# Delegated to image-sizes.sh, which is also runnable on its own.
echo
"$(dirname "$0")/image-sizes.sh"
