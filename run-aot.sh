#!/usr/bin/env bash
#
# Run the aot image (JDK AOT cache — the fast-startup showcase) built by
# ./build-image.sh, publishing its HTTP port. Foreground; Ctrl-C stops it and
# the container is removed on exit.
#
#   ./run-aot.sh   # docker run minimal-java:aot -> http://localhost:8080
#
set -euo pipefail

echo "Running minimal-java:aot -> http://localhost:8080/  (Ctrl-C to stop)"
exec docker run --rm --name minimal-java-aot -p 8080:8080 minimal-java:aot
