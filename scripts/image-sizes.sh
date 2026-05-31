#!/usr/bin/env bash
#
# Size comparison for the images built by build-images.sh: the full Ubuntu base
# and the naive fat-jar image vs the chiseled series, as a tidy per-architecture
# table. The security/startup analogues are cve-counts.sh and startup-times.sh.
#
# Sizes come from `docker image inspect --platform ... --format '{{.Size}}'` (the
# image's content size, in bytes) — a stable machine interface, so there's no
# parsing of formatted output to break when Docker changes its display.
#
# Run after building (the minimal-java/*:local images must be local):
#
#   build-images.sh
#   image-sizes.sh
#
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

UBUNTU_VERSION="$(sed -n 's/^ARG UBUNTU_VERSION=//p' images/ubuntu/Dockerfile)"

# inspect reads only local images, so pull the full Ubuntu base (both arches)
# first; the minimal-java/*:local images are already local from the build.
docker pull --quiet --platform linux/amd64 "ubuntu:${UBUNTU_VERSION}" >/dev/null
docker pull --quiet --platform linux/arm64 "ubuntu:${UBUNTU_VERSION}" >/dev/null

# Print one table row: image label + content size (decimal MB) per arch. A
# missing image inspects as 0 rather than aborting the run.
size() {  # $1 = image ref, $2 = label
  local amd64 arm64
  amd64="$(docker image inspect --platform linux/amd64 "$1" --format '{{.Size}}' 2>/dev/null || echo 0)"
  arm64="$(docker image inspect --platform linux/arm64 "$1" --format '{{.Size}}' 2>/dev/null || echo 0)"
  awk -v l="$2" -v a="$amd64" -v b="$arm64" \
    'BEGIN { printf "  %-26s %8.1f MB %8.1f MB\n", l, a/1e6, b/1e6 }'
}

echo "Size comparison (image size, decimal MB):"
echo
printf '  %-26s %11s %11s\n' "image" "amd64" "arm64"
size "ubuntu:${UBUNTU_VERSION}"     "ubuntu:${UBUNTU_VERSION} (full)"
size "minimal-java/ubuntu:local"     "minimal-java/ubuntu"
size "minimal-java/jre:local"        "minimal-java/jre"
size "minimal-java/fat:local"        "minimal-java/fat (naive)"
size "minimal-java/app:local"        "minimal-java/app"
size "minimal-java/jvm-aot:local"    "minimal-java/jvm-aot"
size "minimal-java/spring-aot:local" "minimal-java/spring-aot"
