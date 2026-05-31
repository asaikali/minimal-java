#!/usr/bin/env bash
#
# Run the app image (no AOT) built by ./build-image.sh, publishing its HTTP
# port. Foreground; Ctrl-C stops it and the container is removed on exit.
#
#   ./run-app.sh   # docker run minimal-java:app -> http://localhost:8080
#
set -euo pipefail

echo "Running minimal-java:app -> http://localhost:8080/  (Ctrl-C to stop)"
exec docker run --rm --name minimal-java-app -p 8080:8080 minimal-java:app
