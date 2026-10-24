#!/usr/bin/env bash
# Smoke test: code-server starts, reports healthy and serves its login page in the platform's security context. Run by the central pipeline
# (DHBW-AppStore-T3/app-registry) against the locally built image, before the Trivy scan and before any push.
# IMAGE and PLATFORM_RUN_FLAGS (--user 1000:1000 --read-only --cap-drop ALL --security-opt no-new-privileges
# --network host) come from the pipeline; the pipeline removes the container afterwards.
set -euo pipefail

# shellcheck disable=SC2086  # PLATFORM_RUN_FLAGS is meant to split into words
docker run -d --name ide $PLATFORM_RUN_FLAGS \
  --tmpfs /tmp --tmpfs /home/coder:uid=1000,gid=1000 \
  -e PASSWORD=ci-smoke-test \
  "$IMAGE"

ok=0
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://[::1]:8080/healthz"; then ok=1; break; fi
  sleep 2
done
docker logs ide
[ "$ok" = 1 ]

# Capture the body first: with pipefail, `curl | grep -q` can fail with SIGPIPE once grep has matched.
login=$(curl -fsS "http://[::1]:8080/login")
grep -qi "password" <<<"$login"
docker rm -f ide >/dev/null

# The team's assignment ZIP (appstore.yaml variable "assignments") is unpacked once into ~/Coding-Aufgabe.
# shellcheck disable=SC2086
docker run -d --name ide-zip $PLATFORM_RUN_FLAGS \
  --tmpfs /tmp --tmpfs /home/coder:uid=1000,gid=1000 \
  -v "$PWD/aufgaben.zip:/opt/online-ide/assignment.zip:ro" \
  -e PASSWORD=ci-smoke-test \
  "$IMAGE"
for _ in $(seq 1 30); do
  docker exec ide-zip test -e /home/coder/Coding-Aufgabe/.appstore-unpacked && break
  sleep 1
done
docker logs ide-zip
docker exec ide-zip test -f /home/coder/Coding-Aufgabe/aufgaben/Aufgabe01_HelloWorld.java
if docker exec ide-zip test -e /home/coder/Coding-Aufgabe/__MACOSX; then echo "__MACOSX was unpacked" >&2; exit 1; fi
docker rm -f ide-zip >/dev/null
