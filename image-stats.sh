#!/usr/bin/env bash
#
# Size comparison for the chiseled-image series built by ./build-image.sh:
# the full Ubuntu base vs each chiseled image, side by side, per architecture.
#
# build-image.sh calls this at the end of a build, but it's also runnable on its
# own against images already in the local Docker store — handy for re-checking
# sizes without rebuilding:
#
#   ./image-stats.sh
#
# Reads the Ubuntu version from the Dockerfile's ARG line (the single source of
# truth) so the base it pulls matches the one the series was chiselled from.
#
set -euo pipefail

cd "$(dirname "$0")"

# Same series order as build-image.sh, smallest first.
TARGETS=(ubuntu jre app aot)

# The full Ubuntu base to compare against. Read from the Dockerfile ARG (a plain
# docker pull below, outside any build, so it can't see the ARG itself).
UBUNTU_VERSION="$(sed -n 's/^ARG UBUNTU_VERSION=//p' Dockerfile)"

# Pull the full Ubuntu base for both arches so we can show a like-for-like
# (uncompressed disk usage) comparison against the chiseled results.
docker pull --quiet --platform linux/amd64 "ubuntu:${UBUNTU_VERSION}" >/dev/null
docker pull --quiet --platform linux/arm64 "ubuntu:${UBUNTU_VERSION}" >/dev/null

echo "Size comparison (ubuntu base -> chiseled series):"
echo
# --tree prints per-architecture sizes in MB (no manual formatting needed).
docker image ls --tree "ubuntu:${UBUNTU_VERSION}"
for target in "${TARGETS[@]}"; do
  echo
  docker image ls --tree "minimal-java:${target}"
done
