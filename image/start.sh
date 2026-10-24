#!/bin/sh
# Start of an IDE pod. The deploying teacher can upload one ZIP of assignments
# per team (variable "assignments" of appstore.yaml, mounted read-only at
# $ASSIGNMENT_ZIP); it is unpacked into ~/Coding-Aufgabe once, at the first
# start of the person's workspace, as the VM version did. Later starts leave
# the work there alone. No sudo, no root: the platform runs this as an
# unprivileged user with a read-only root filesystem.
set -eu

ZIP="${ASSIGNMENT_ZIP:-/opt/online-ide/assignment.zip}"
DEST="${HOME:-/home/coder}/Coding-Aufgabe"
MARK="$DEST/.appstore-unpacked"

if [ -f "$ZIP" ] && [ ! -e "$MARK" ]; then
    mkdir -p "$DEST"
    # unzip drops absolute paths and ../ components; macOS metadata is skipped.
    if unzip -o -q "$ZIP" -d "$DEST" -x '__MACOSX/*' '*/.DS_Store' '.DS_Store'; then
        touch "$MARK"
        echo "online-ide: assignments unpacked into $DEST"
    else
        echo "online-ide: could not unpack $ZIP, starting without the assignments" >&2
    fi
fi

exec dumb-init /usr/bin/code-server "$@"
