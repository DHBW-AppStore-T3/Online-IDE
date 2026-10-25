#!/bin/sh
# Start of an IDE pod. The deploying teacher can upload one ZIP of assignments
# per team (variable "assignments" of appstore.yaml, mounted read-only at
# $ASSIGNMENT_ZIP); it is unpacked into ~/Coding-Aufgabe once, at the first
# start of the person's workspace, as the VM version did. Later starts leave
# the work there alone. No sudo, no root: the platform runs this as an
# unprivileged user with a read-only root filesystem.
#
# The unpacking is done by unpack-assignments.py, which checks the whole archive first (entry count, real
# unpacked size, paths, links, encryption) and writes everything or nothing. A rejected or broken ZIP is
# logged and the IDE starts with an empty workspace; it never keeps the IDE from starting.
set -eu

ZIP="${ASSIGNMENT_ZIP:-/opt/online-ide/assignment.zip}"
DEST="${HOME:-/home/coder}/Coding-Aufgabe"

if [ -f "$ZIP" ]; then
    /usr/bin/python3 /usr/local/bin/online-ide-unpack "$ZIP" "$DEST" \
        || echo "online-ide: starting without the assignments" >&2
fi

exec dumb-init /usr/bin/code-server "$@"
