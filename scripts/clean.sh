#!/usr/bin/env bash
#
# Remove what build-images.sh, publish-artifact.sh, run-*.sh and startup-times.sh
# create locally: the minimal-java/*:local images, any containers they leave
# behind, and the staged jars. Upstream base images (ubuntu, eclipse-temurin),
# the shared buildx builder, and any ghcr.io tags push-images.sh created are left
# alone.
#
#   ./scripts/clean.sh
#
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Force-remove a container or image if it exists, reporting only what was there.
rm_container() { docker rm -f "$1"       >/dev/null 2>&1 && echo "removed container $1" || true; }
rm_image()     { docker image rm -f "$1" >/dev/null 2>&1 && echo "removed image $1"     || true; }

# Containers the run/startup scripts may strand (they normally --rm themselves,
# but a crashed or interrupted run can leave one behind).
rm_container minimal-java-fat
rm_container minimal-java-jvm-aot
rm_container minimal-java-spring-aot
rm_container minimal-java-app
rm_container bench-fat
rm_container bench-app
rm_container bench-jvm-aot
rm_container bench-spring-aot

# The built image series.
rm_image minimal-java/golden-ubuntu:local
rm_image minimal-java/golden-jre:local
rm_image minimal-java/fat:local
rm_image minimal-java/app:local
rm_image minimal-java/jvm-aot:local
rm_image minimal-java/spring-aot:local

# The staged jars produced by publish-artifact.sh --local.
rm -rf stage && echo "removed stage/" || true

echo "clean."
