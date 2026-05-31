#!/usr/bin/env bash
#
# Build the series of chiseled-Ubuntu images defined in ./Dockerfile, one per
# Dockerfile target, each progressively richer:
#
#   ubuntu — chiseled Ubuntu (base-files + libc6) only
#   jre    — chiseled ubuntu + a trimmed Eclipse Temurin JRE 25
#   app    — jre + the Spring Boot app, exploded into Spring Boot layers
#   aot    — jre + the app layout + a JDK 25 AOT cache, for faster startup
#
# Each is built multi-arch (linux/amd64 + linux/arm64) so it runs on both
# Apple Silicon Macs and amd64 Linux, and tagged minimal-java:<target>.
#
# Builds both arches and loads each manifest into the local Docker store so you
# can run them immediately. Loading a multi-arch manifest requires the containerd
# image store (Docker Desktop: Settings > General > "Use containerd for pulling
# and storing images"); the legacy image store can't hold one.
#
#   ./build-image.sh    # build minimal-java:{ubuntu,jre,app,aot}
#
# To publish the built series to a registry, build first, then ./push-image.sh.
#
# Image versions (Ubuntu, JRE, chisel) are NOT set here — they live in the
# Dockerfile's ARG lines, the single source of truth. To change one, edit the
# Dockerfile (which is also what Renovate updates).
#
set -euo pipefail

cd "$(dirname "$0")"

BUILDER="chisel-builder"

# Multi-platform builds and QEMU emulation need the docker-container driver;
# the default "docker" driver can't do either. Create the builder on demand.
if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
  echo "Creating buildx builder '${BUILDER}' (docker-container driver)..."
  docker buildx create --name "${BUILDER}" --driver docker-container --bootstrap >/dev/null
fi

# Build one Dockerfile target multi-arch and load it into the local Docker store
# as minimal-java:<target>. --sbom/--provenance attach a Software Bill of
# Materials and SLSA build provenance to each image; they travel with it when
# pushed, where `docker buildx imagetools inspect <registry-ref>` can show them
# (attestations aren't inspectable on a local-only image).
build() {
  local target="$1"
  echo
  echo ">>> minimal-java:${target} (--target ${target})"
  docker buildx build \
    --builder "${BUILDER}" \
    --platform linux/amd64,linux/arm64 \
    --sbom=true --provenance=mode=max \
    --target "${target}" --tag "minimal-java:${target}" --load .
}

# Build the series, smallest first. The jre build runs a RUN step (trimming the
# JRE launchers) that executes emulated for the non-native arch, so its first
# build is noticeably slower than the others.
build ubuntu
build jre
build app
build aot

# The naive baseline, for the comparison scripts: the fat jar on the full
# Temurin JRE, with none of the techniques applied.
build fat

# Size comparison: full Ubuntu base vs each chiseled image, side by side.
# Delegated to compare-image-sizes.sh, which is also runnable on its own to
# re-check sizes later.
echo
./compare-image-sizes.sh
