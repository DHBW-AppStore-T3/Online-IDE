"""Tests of the image's assignment unpacker, run INSIDE the container by .github/smoke-test.sh:

    docker exec -i ide python3 - < .github/test-unpack.py

Every hostile archive is built here, in /tmp of the container, and unpacked with the real
/usr/local/bin/online-ide-unpack as the platform's unprivileged user. The test passes if each hostile
archive is rejected (exit status 3) without leaving anything behind, and a good one is unpacked exactly.
"""

import io
import os
import shutil
import stat
import struct
import subprocess
import sys
import time
import zipfile
import zlib

UNPACK = "/usr/local/bin/online-ide-unpack"
WORK = "/tmp/unpack-test"
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def make_zip(entries, compress=zipfile.ZIP_DEFLATED):
    """entries: name -> bytes | (bytes, unix_mode)"""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, value in entries.items():
            content, mode = value if isinstance(value, tuple) else (value, 0o100644)
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = mode << 16
            info.compress_type = compress
            z.writestr(info, content)
    return buf.getvalue()


counter = [0]


def run(data, prefill=None):
    """Unpack `data`; return (exit status, destination directory, stderr)."""
    counter[0] += 1
    base = f"{WORK}/case{counter[0]}"
    os.makedirs(base)
    zip_path = f"{base}/a.zip"
    with open(zip_path, "wb") as handle:
        handle.write(data)
    dest = f"{base}/home/Coding-Aufgabe"
    if prefill:
        for name, content in prefill.items():
            os.makedirs(os.path.dirname(f"{dest}/{name}"), exist_ok=True)
            with open(f"{dest}/{name}", "wb") as handle:
                handle.write(content)
    started = time.time()
    result = subprocess.run(["python3", UNPACK, zip_path, dest], capture_output=True, text=True)
    return result.returncode, dest, result.stderr + result.stdout, time.time() - started


def tree(root):
    found = []
    for current, dirs, files in os.walk(root):
        for name in dirs + files:
            found.append(os.path.relpath(os.path.join(current, name), root))
    return sorted(found)


def rejected(label, data):
    status, dest, output, seconds = run(data)
    check(status == 3, f"{label}: expected status 3, got {status} ({output.strip()})")
    check(not os.path.exists(dest) or tree(dest) == [], f"{label}: left files behind: {tree(dest) if os.path.exists(dest) else ''}")
    check(not os.path.exists(os.path.join(dest, ".appstore-unpacked")), f"{label}: wrote the marker")
    check(not os.path.exists(dest + ".unpacking"), f"{label}: left the staging directory")
    check(seconds < 30, f"{label}: took {seconds:.0f} s")
    return output


os.makedirs(WORK)

# ---- a good archive
good = make_zip(
    {
        "aufgaben/": b"",
        "aufgaben/Aufgabe01.java": b"class A {}\n",
        "aufgaben/sub/Aufgabe02.java": b"class B {}\n",
        "__MACOSX/aufgaben/._Aufgabe01.java": b"mac",
        "aufgaben/.DS_Store": b"mac",
        "aufgaben/script.sh": (b"#!/bin/sh\necho hi\n", 0o100755),
    }
)
status, dest, output, _ = run(good)
check(status == 0, f"good: status {status} {output}")
check(
    tree(dest) == [".appstore-unpacked", "aufgaben", "aufgaben/Aufgabe01.java", "aufgaben/script.sh", "aufgaben/sub", "aufgaben/sub/Aufgabe02.java"],
    f"good: unexpected tree {tree(dest)}",
)
check(stat.S_IMODE(os.stat(f"{dest}/aufgaben/script.sh").st_mode) == 0o644, "good: files are not made executable")
check(not os.path.exists(dest + ".unpacking"), "good: left the staging directory")

# ---- the marker keeps a second start from touching the student's work
with open(f"{dest}/aufgaben/Aufgabe01.java", "w") as handle:
    handle.write("my own work\n")
zip_path = os.path.join(os.path.dirname(os.path.dirname(dest)), "a.zip")
again = subprocess.run(["python3", UNPACK, zip_path, dest], capture_output=True, text=True)
check(again.returncode == 0, "second start: status")
check(open(f"{dest}/aufgaben/Aufgabe01.java").read() == "my own work\n", "second start: overwrote the student's file")

# ---- never overwrite what is already there (marker missing, e.g. after a failed first start)
status, dest, output, _ = run(good, prefill={"aufgaben/Aufgabe01.java": b"already here\n"})
check(status == 0, f"no-clobber: status {status}")
check(open(f"{dest}/aufgaben/Aufgabe01.java").read() == "already here\n", "no-clobber: overwrote an existing file")
check(os.path.exists(f"{dest}/aufgaben/sub/Aufgabe02.java"), "no-clobber: did not add the missing file")

# ---- hostile archives: all rejected as a whole, nothing left behind
for name, label in [
    ("../../escape.txt", "zip-slip"),
    ("a/../../escape.txt", "zip-slip nested"),
    ("/tmp/absolute.txt", "absolute path"),
    ("C:/drive.txt", "drive letter"),
    ("back\\slash.txt", "backslash"),
    ("ctrl\x07char.txt", "control character"),
    ("./dot.txt", "dot component"),
    ("a//b.txt", "empty component"),
    ("d/" * 40 + "deep.txt", "too deep"),
    ("x" * 300, "name too long"),
]:
    rejected(label, make_zip({"ok.txt": b"fine", name: b"x"}))
for tmp_leak in ("/tmp/escape.txt", "/tmp/absolute.txt", f"{WORK}/escape.txt", f"{WORK}/case1/escape.txt"):
    check(not os.path.exists(tmp_leak), f"something was written outside the destination: {tmp_leak}")

for mode, label in [
    (stat.S_IFLNK | 0o777, "symlink"),
    (stat.S_IFCHR | 0o666, "character device"),
    (stat.S_IFBLK | 0o660, "block device"),
    (stat.S_IFIFO | 0o644, "fifo"),
]:
    rejected(label, make_zip({"ok.txt": b"fine", "bad": (b"/etc/passwd", mode)}))

# symlink + a file through it: the classic way out of the directory
rejected("symlink then file through it", make_zip({"lnk": (b"/tmp", stat.S_IFLNK | 0o777), "lnk/through.txt": b"x"}))
check(not os.path.exists("/tmp/through.txt"), "symlink: wrote through the link")

encrypted = bytearray(make_zip({"secret.txt": b"x" * 20}))
struct.pack_into("<H", encrypted, encrypted.rindex(b"PK\x01\x02") + 8, 0x1)
rejected("encrypted", bytes(encrypted))

rejected("bzip2", make_zip({"a.txt": b"x" * 200}, compress=zipfile.ZIP_BZIP2))
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w") as z:
    z.writestr("a.txt", b"1")
    z.writestr("A.TXT", b"2")
rejected("duplicate names (case)", buf.getvalue())
rejected("empty archive", make_zip({}))
rejected("not a zip", b"MZ this is not a zip file at all" * 5)
rejected("truncated zip", good[: len(good) // 2])
rejected("too many entries", make_zip({f"f{i}.txt": b"" for i in range(2001)}))

# decompression bomb: ~1 MiB of archive, 100 MiB of zeros
bomb = make_zip({"big.bin": b"\x00" * (100 * 1024 * 1024)})
check(len(bomb) < 1024 * 1024, "bomb: the test archive is not small enough")
rejected("decompression bomb", bomb)
many = make_zip({f"p{i}.bin": b"\x00" * (8 * 1024 * 1024) for i in range(10)})
rejected("many medium entries", many)
check(shutil.disk_usage("/tmp").free > 0, "disk")

# header that lies about the size, corrupt content
lying = bytearray(make_zip({"a.txt": b"hello world" * 100}, compress=zipfile.ZIP_STORED))
struct.pack_into("<I", lying, lying.rindex(b"PK\x01\x02") + 24, 5)
rejected("header lies about the size", bytes(lying))
corrupt = bytearray(make_zip({"a.txt": b"hello world" * 100}, compress=zipfile.ZIP_STORED))
corrupt[40] ^= 0xFF
rejected("corrupt content (CRC)", bytes(corrupt))

# entries that share compressed bytes (overlapping-entry bomb)
payload = b"A" * 100_000
local = struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0, 0, 0, 0x21, zlib.crc32(payload), len(payload), len(payload), 1, 0) + b"a" + payload
central = b"".join(
    struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0, 0, 0, 0x21, zlib.crc32(payload), len(payload), len(payload), 1, 0, 0, 0, 0, 0, 0)
    + bytes([ord("a") + i])
    for i in range(5)
)
end = struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, 5, 5, len(central), len(local), 0)
rejected("overlapping entries", local + central + end)

# an archive file larger than the limit
rejected("archive file too large", make_zip({"big.bin": os.urandom(2 * 1024 * 1024 + 1)}, compress=zipfile.ZIP_STORED))

# a file where a directory is needed
status, dest, output, _ = run(make_zip({"a": b"file", "a/b": b"x"}))
check(status in (3, 4), f"file and directory with one name: status {status}")
check(not os.path.exists(os.path.join(dest, ".appstore-unpacked")), "file and directory with one name: wrote the marker")

shutil.rmtree(WORK, ignore_errors=True)
if failures:
    print(f"{len(failures)} unpack test(s) failed")
    sys.exit(1)
print("unpack tests: all passed")
