#!/usr/bin/env bash
#
# Run one of the chiseled images built by ./build-image.sh. Defaults to the
# AOT-cached app image and publishes its HTTP port, so:
#
#   ./run-image.sh            # docker run minimal-java:aot, http://localhost:8080
#   ./run-image.sh app        # run the non-AOT app image instead
#   PORT=9090 ./run-image.sh  # publish on a different host port
#
# Runs in the foreground (Ctrl-C to stop) and removes the container on exit.
#
# Environment overrides:
#   REPO   image repository           (default: minimal-java)
#   PORT   host port to publish 8080   (default: 8080)
#   NAME   container name              (default: <repo>-<tag>)
#
set -euo pipefail

TAG="${1:-aot}"
REPO="${REPO:-minimal-java}"
PORT="${PORT:-8080}"
IMAGE="${REPO}:${TAG}"
NAME="${NAME:-${REPO}-${TAG}}"

echo "Running ${IMAGE} -> http://localhost:${PORT}/"
echo "(Ctrl-C to stop)"

exec docker run --rm --name "${NAME}" -p "${PORT}:8080" "${IMAGE}"
