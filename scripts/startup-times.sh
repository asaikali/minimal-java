#!/usr/bin/env bash
#
# Simple startup comparison for the images built by build-images.sh: run the
# fat-jar baseline (no techniques), then the app image (extracted layers, no
# AOT), then the jvm-aot image (JDK AOT cache), then the spring-aot image
# (JDK AOT cache + Spring AOT), showing each container's full startup log. At the
# end it prints Spring Boot's own "Started ... in N seconds" line for all four
# together — the startup story (fat jar -> extracted -> JDK AOT cache -> + Spring
# AOT) behind the README's "~4.8x faster startup" claim.
#
#   build-images.sh             # build the images first
#   startup-times.sh
#
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

PORT=18080
summary=""

# Bold the app:/jvm-aot:/spring-aot: labels in the final summary, but only when writing to a
# terminal so piped output stays free of escape codes.
if [[ -t 1 ]]; then bold=$'\e[1m'; reset=$'\e[0m'; else bold=""; reset=""; fi

# Start one image, wait (quietly) until GET / first answers, print its full
# startup log, remove the container, and append its "Started ..." line to the
# summary printed once all are done.
boot() {
  local logs
  echo ">>> minimal-java:$1"
  docker run --name "bench-$1" -p "${PORT}:8080" -d "minimal-java:$1" >/dev/null
  until curl -fsS -o /dev/null "http://localhost:${PORT}/" 2>/dev/null; do sleep 0.1; done

  logs="$(docker logs "bench-$1" 2>&1)"
  docker rm -f "bench-$1" >/dev/null

  echo "${logs}"
  echo
  summary+="${bold}$1:${reset} $(echo "${logs}" | grep 'Started Application' || true)"$'\n'
}

boot fat
boot app
boot jvm-aot
boot spring-aot

echo "=== startup ==="
printf '%s' "${summary}"
