#!/usr/bin/env bash
#
# Remove what build-images.sh, run-*.sh and startup-times.sh create locally: the
# minimal-java:* images, any containers they leave behind, and the chisel-builder
# buildx builder. Upstream base images (ubuntu, eclipse-temurin) are left alone,
# as are any ghcr.io/<repo>:* tags push-images.sh created.
#
#   ./scripts/clean.sh
#
set -euo pipefail

# Force-remove a container or image if it exists, reporting only what was there.
rm_container() { docker rm -f "$1"       >/dev/null 2>&1 && echo "removed container $1" || true; }
rm_image()     { docker image rm -f "$1" >/dev/null 2>&1 && echo "removed image $1"     || true; }

# Containers the run/startup scripts may strand (they normally --rm themselves,
# but a crashed or interrupted run can leave one behind).
rm_container minimal-java-aot
rm_container minimal-java-app
rm_container bench-fat
rm_container bench-app
rm_container bench-aot

# The built image series.
rm_image minimal-java:ubuntu
rm_image minimal-java:jre
rm_image minimal-java:fat
rm_image minimal-java:app
rm_image minimal-java:aot

# The on-demand multi-arch builder.
docker buildx rm chisel-builder >/dev/null 2>&1 && echo "removed buildx builder chisel-builder" || true

echo "clean."
