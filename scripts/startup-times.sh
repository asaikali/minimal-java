#!/usr/bin/env bash
#
# Simple startup comparison for the images built by build-images.sh: run the
# fat-jar baseline (no techniques), then the app image (extracted layers, no
# AOT), then the aot image (AOT cache), showing each container's full startup
# log. At the end it prints Spring Boot's own "Started ... in N seconds" line
# for all three together — the startup story (fat jar -> extracted -> AOT cache)
# behind the README's "~3.6x faster startup" claim.
#
#   build-images.sh             # build the images first
#   startup-times.sh
#
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

PORT=18080
summary=""

# Bold the app:/aot: labels in the final summary, but only when writing to a
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
boot aot

echo "=== startup ==="
printf '%s' "${summary}"
