#!/usr/bin/env bash
# Smoke test: code-server starts, reports healthy and serves its login page in the platform's security context,
# the student toolchain works, and the assignment unpacker survives hostile archives. Run by the central pipeline
# (DHBW-AppStore-T3/app-registry) against the locally built image, before the Trivy scan and before any push.
# IMAGE and PLATFORM_RUN_FLAGS (--user 1000:1000 --read-only --cap-drop ALL --security-opt no-new-privileges
# --network host) come from the pipeline; the pipeline removes the container afterwards.
set -euo pipefail

# /tmp and the volume allow exec in the cluster (emptyDir, PVC); docker's tmpfs does not unless told to.
# shellcheck disable=SC2086  # PLATFORM_RUN_FLAGS is meant to split into words
docker run -d --name ide $PLATFORM_RUN_FLAGS \
  --tmpfs /tmp:exec,size=512m --tmpfs /home/coder:uid=1000,gid=1000,exec \
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

# The tools the VM version (v1.x) gave the students: compiler, Python, Node and the usual download tools.
docker exec ide sh -c 'python3 --version && pip --version && node --version && npm --version && gcc --version | head -1 \
  && make --version | head -1 && git --version && curl --version | head -1 && wget --version | head -1'
out=$(docker exec ide sh -c 'cd /tmp && printf "#include <stdio.h>\nint main(void){puts(\"hello-c\");return 0;}\n" > hello.c \
  && gcc hello.c -o hello && ./hello')
grep -qx "hello-c" <<<"$out"
out=$(docker exec ide sh -c 'python3 -m venv /home/coder/venv && /home/coder/venv/bin/python -c "print(\"hello-venv\")"')
grep -qx "hello-venv" <<<"$out"
out=$(docker exec ide sh -c 'node -e "console.log(\"hello-node\")"')
grep -qx "hello-node" <<<"$out"
# The root filesystem is read-only: pip installs into ~/.local, npm -g into ~/.npm-global (see the Dockerfile).
out=$(docker exec ide python3 -c "import site; print(site.getusersitepackages())")
grep -q "^/home/coder/.local/" <<<"$out"
out=$(docker exec ide npm config get prefix)
grep -qx "/home/coder/.npm-global" <<<"$out"

# The assignment unpacker against hostile archives (zip-slip, links, bombs, overlapping entries, ...), run as
# the platform's unprivileged user in the platform's security context.
docker exec -i ide python3 - < .github/test-unpack.py
docker rm -f ide >/dev/null

# The team's assignment ZIP (appstore.yaml variable "assignments") is unpacked once into ~/Coding-Aufgabe.
# shellcheck disable=SC2086
docker run -d --name ide-zip $PLATFORM_RUN_FLAGS \
  --tmpfs /tmp:exec,size=512m --tmpfs /home/coder:uid=1000,gid=1000,exec \
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
