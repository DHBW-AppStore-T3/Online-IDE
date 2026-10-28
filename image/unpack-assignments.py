#!/usr/bin/env python3
"""Unpack the team's assignment ZIP into a directory, completely or not at all.

    unpack-assignments.py <zip> <destination>

The ZIP comes from the person who deploys the app (variable "assignments"); the backend already checks
it, and this script does not rely on that: the image is the last line of defence in front of the
student's volume. The rules are the backend's (app/services/upload_validation.py in the backend
repository), kept in step by hand:

* the whole archive is inspected before anything is written: at most MAX_ENTRIES entries, MAX_ENTRY_BYTES
  per entry and MAX_TOTAL_BYTES in total, counted on the bytes that really come out of the decompressor
  (the sizes in the headers are only compared with them); every CRC is verified
* a single bad entry rejects the archive: absolute paths, "..", "." or empty components, backslashes,
  control characters, over-long or too deeply nested paths, duplicate names (also by case), symbolic
  links and device files, encrypted entries, compression other than stored/deflate, entries that share
  compressed bytes
* files are written into a fresh staging directory next to the destination (regular files and
  directories only, never following a link, mode 0644/0755, nothing is executed), and only a complete
  result is moved into place; existing files are never overwritten
* macOS metadata (__MACOSX/, .DS_Store, ._*) is left out silently
* editor and Git configuration is left out, with a note on stderr: a ".vscode", ".devcontainer" or ".git"
  directory (at any depth) is not unpacked. Workspace tasks, settings and devcontainer files can run
  commands as soon as a student opens the folder and clicks "trust", and ".git/config" or ".git/hooks" run
  them on the first git command; an assignment ZIP is not a place for them

Exit status: 0 unpacked, 3 rejected (the reason goes to stderr), 4 error while writing.
"""

from __future__ import annotations

import os
import re
import shutil
import stat
import sys
import zipfile

MAX_ZIP_BYTES = 2 * 1024 * 1024
MAX_ENTRIES = 2000
MAX_ENTRY_BYTES = 32 * 1024 * 1024
MAX_TOTAL_BYTES = 64 * 1024 * 1024
MAX_PATH_LENGTH = 1024
MAX_COMPONENT_LENGTH = 255
MAX_DEPTH = 32
CHUNK = 64 * 1024
MARKER = ".appstore-unpacked"
# Directories whose content tells the editor or Git to run something (compared case-insensitively).
CONFIG_DIRECTORIES = frozenset({".vscode", ".devcontainer", ".git"})


class Rejected(Exception):
    pass


def check_name(name: str) -> None:
    if not name or len(name) > MAX_PATH_LENGTH:
        raise Rejected("an entry has an empty or too long path")
    if any(ord(ch) < 0x20 or ord(ch) == 0x7F for ch in name):
        raise Rejected("an entry path contains control characters")
    if "\\" in name:
        raise Rejected("an entry path contains a backslash")
    if name.startswith("/") or re.match(r"^[A-Za-z]:", name):
        raise Rejected("an entry has an absolute path")
    parts = name.rstrip("/").split("/")
    if len(parts) > MAX_DEPTH:
        raise Rejected("an entry path is nested too deeply")
    for part in parts:
        if part in ("", ".", ".."):
            raise Rejected("an entry path contains '.', '..' or an empty component")
        if len(part) > MAX_COMPONENT_LENGTH:
            raise Rejected("an entry path component is too long")


def is_mac_metadata(name: str) -> bool:
    parts = name.rstrip("/").split("/")
    return parts[0] == "__MACOSX" or parts[-1] == ".DS_Store" or parts[-1].startswith("._")


def is_editor_config(name: str) -> bool:
    return any(part.casefold() in CONFIG_DIRECTORIES for part in name.rstrip("/").split("/"))


def inspect(archive: zipfile.ZipFile, data_length: int) -> tuple[list[zipfile.ZipInfo], int]:
    """Return the entries to unpack and how many editor/Git configuration entries were left out; raise Rejected.

    Every entry is checked, the ones that are left out as well: a hostile name rejects the archive
    whether or not the entry would have been written."""
    infos = archive.infolist()
    if not infos:
        raise Rejected("the archive is empty")
    if len(infos) > MAX_ENTRIES:
        raise Rejected(f"more than {MAX_ENTRIES} entries")
    seen: set[str] = set()
    compressed = 0
    for info in infos:
        check_name(info.filename)
        folded = info.filename.rstrip("/").casefold()
        if folded in seen:
            raise Rejected("two entries have the same path")
        seen.add(folded)
        if info.flag_bits & 0x1:
            raise Rejected("the archive has encrypted entries")
        if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            raise Rejected("the archive uses an unsupported compression method")
        mode = info.external_attr >> 16 if info.create_system == 3 else 0
        if mode and (stat.S_ISLNK(mode) or stat.S_ISCHR(mode) or stat.S_ISBLK(mode) or stat.S_ISFIFO(mode) or stat.S_ISSOCK(mode)):
            raise Rejected("the archive contains a symbolic link or a device file")
        if info.is_dir() and info.file_size:
            raise Rejected("a directory entry has content")
        if info.file_size > MAX_ENTRY_BYTES:
            raise Rejected("an entry is larger than the limit")
        compressed += info.compress_size
    if compressed > data_length:
        raise Rejected("the archive's entries overlap")
    wanted = [i for i in infos if not is_mac_metadata(i.filename)]
    kept = [i for i in wanted if not is_editor_config(i.filename)]
    return kept, len(wanted) - len(kept)


def write_entries(archive: zipfile.ZipFile, entries: list[zipfile.ZipInfo], staging: str) -> None:
    """Decompress every entry once, counting real bytes, into the staging directory."""
    total = 0
    for info in entries:
        target = os.path.join(staging, *info.filename.rstrip("/").split("/"))
        if info.is_dir():
            os.makedirs(target, mode=0o755, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(target), mode=0o755, exist_ok=True)
        written = 0
        # O_EXCL | O_NOFOLLOW: never write through something that already exists.
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
        with os.fdopen(fd, "wb") as out, archive.open(info) as source:
            while True:
                chunk = source.read(CHUNK)
                if not chunk:
                    break
                written += len(chunk)
                total += len(chunk)
                if written > MAX_ENTRY_BYTES or total > MAX_TOTAL_BYTES:
                    raise Rejected("the archive unpacks to more than the limit")
                out.write(chunk)
        if written != info.file_size:
            raise Rejected("an entry's real size differs from its header")


def verify_inside(staging: str) -> None:
    """Belt and braces: everything under staging is a regular file or directory, and stays inside."""
    root = os.path.realpath(staging)
    for current, dirs, files in os.walk(staging):
        for name in dirs + files:
            path = os.path.join(current, name)
            if os.path.islink(path) or os.path.commonpath([root, os.path.realpath(path)]) != root:
                raise Rejected("an unpacked entry is a link or leaves the target directory")


def move_into_place(staging: str, destination: str) -> None:
    """Merge staging into destination without overwriting anything that is already there."""
    for current, dirs, files in os.walk(staging):
        relative = os.path.relpath(current, staging)
        target_dir = destination if relative == "." else os.path.join(destination, relative)
        os.makedirs(target_dir, mode=0o755, exist_ok=True)
        for name in files:
            target = os.path.join(target_dir, name)
            if not os.path.lexists(target):
                os.replace(os.path.join(current, name), target)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    zip_path, destination = argv[1], argv[2].rstrip("/")
    marker = os.path.join(destination, MARKER)
    if os.path.exists(marker):
        return 0
    staging = destination + ".unpacking"
    shutil.rmtree(staging, ignore_errors=True)
    try:
        if os.path.getsize(zip_path) > MAX_ZIP_BYTES:
            raise Rejected("the archive file is larger than the limit")
        with open(zip_path, "rb") as handle:
            data = handle.read(MAX_ZIP_BYTES + 1)
        try:
            archive = zipfile.ZipFile(zip_path)
        except (zipfile.BadZipFile, OSError, ValueError):
            raise Rejected("not a readable ZIP archive") from None
        with archive:
            entries, left_out = inspect(archive, len(data))
            if left_out:
                print(
                    f"online-ide: {left_out} entries of editor/Git configuration "
                    f"({', '.join(sorted(CONFIG_DIRECTORIES))}) were not unpacked",
                    file=sys.stderr,
                )
            os.makedirs(staging, mode=0o700)
            try:
                write_entries(archive, entries, staging)
            except (zipfile.BadZipFile, NotImplementedError, RuntimeError, EOFError, ValueError) as exc:
                raise Rejected(f"an entry cannot be read ({exc.__class__.__name__})") from None
        verify_inside(staging)
        os.makedirs(destination, mode=0o755, exist_ok=True)
        move_into_place(staging, destination)
        with open(marker, "w", encoding="utf-8") as handle:
            handle.write("unpacked\n")
    except Rejected as exc:
        print(f"online-ide: assignments rejected: {exc}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"online-ide: assignments could not be written: {exc.__class__.__name__}: {exc}", file=sys.stderr)
        return 4
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    print(f"online-ide: assignments unpacked into {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
