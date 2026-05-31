#!/usr/bin/env bash
#
# Run the fat image (the naive baseline — Part 1 of the tutorial) built by
# build-images.sh, publishing its HTTP port. Foreground; Ctrl-C stops it and the
# container is removed on exit.
#
#   run-fat.sh   # docker run minimal-java/fat:local -> http://localhost:8080
#
# Deliberately runs PLAIN — no hardening flags. fat is the Spring Boot fat jar on
# the full Temurin JRE: it runs as root, on a full OS with a shell and package
# manager. That's the starting point. Part 2 (docs/2-layering.md) introduces the
# chiseled, non-root image and the hardened run-app.sh that drops capabilities and
# makes the root filesystem read-only — compare the two to see what hardening adds.
#
set -euo pipefail

echo "Running minimal-java/fat:local -> http://localhost:8080/  (Ctrl-C to stop)"
exec docker run --rm --name minimal-java-fat \
  -p 8080:8080 \
  minimal-java/fat:local
