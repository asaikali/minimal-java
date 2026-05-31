#!/usr/bin/env bash
#
# Run the jvm-aot image (JDK 25 / Project Leyden AOT cache — the fast-startup
# showcase) built by build-images.sh, publishing its HTTP port. Foreground;
# Ctrl-C stops it and the container is removed on exit.
#
#   run-jvm-aot.sh   # docker run minimal-java/jvm-aot:local -> http://localhost:8080
#
# Runs hardened, to show the secure-runtime half of the story (the image already
# builds non-root and shell-less):
#   --read-only                        no writes to the root filesystem
#   --tmpfs /tmp                        ...except an in-memory /tmp, which the JVM
#                                       and embedded Tomcat need for scratch files
#   --cap-drop ALL                      drop every Linux capability
#   --security-opt no-new-privileges    block setuid privilege escalation
#
# No HEALTHCHECK: the chiseled image has no shell or curl to run one — in
# Kubernetes you'd use an httpGet readiness/liveness probe instead.
#
set -euo pipefail

echo "Running minimal-java/jvm-aot:local -> http://localhost:8080/  (Ctrl-C to stop)"
exec docker run --rm --name minimal-java-jvm-aot \
  --read-only \
  --tmpfs /tmp \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  -p 8080:8080 \
  minimal-java/jvm-aot:local
