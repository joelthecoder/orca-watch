import fcntl
import json
import os
from pathlib import Path
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / ".build/debug/orca-watch"


def fixture(newest="b"):
    def resource(data):
        return {"available": True, "data": data}

    sessions = []
    terminals = []
    tabs = []
    for name in ["a", "b"]:
        project = "Alpha" if name == "a" else "Beta"
        sessions.append({
            "id": name, "title": f"Task {name.upper()}", "agent": "codex",
            "updatedAt": f"2026-10-29T11:00:{'30' if name == newest else '10'}Z",
            "liveState": "live", "liveBindings": [{"terminal": name, "incarnationId": name, "runtimeId": "r"}],
            "workspaceContexts": [{"projectId": project, "projectName": project}],
        })
        terminals.append({"handle": name, "incarnationId": name, "worktreeId": project, "connected": True})
        tabs.append({"id": name, "terminal": name, "incarnationId": name, "worktreeId": project})
    return {"schemaVersion": 1, "capturedAt": "2026-10-29T11:01:00Z", "historyTruncated": False,
            "runtime": resource({"runtimeId": "r"}), "sessions": resource(sessions),
            "projects": resource([]), "repositories": resource([]), "terminals": resource(terminals), "tabs": resource(tabs)}


def drain(master, duration=0.2):
    output = b""
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        readable, _, _ = select.select([master], [], [], 0.02)
        if readable:
            try:
                output += os.read(master, 65536)
            except OSError:
                break
    return output.decode("utf-8", errors="replace")


def wait_for(master, predicate, timeout=5):
    output = ""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        output += drain(master, 0.1)
        if predicate(output):
            return output
    raise AssertionError(f"Terminal condition timed out: {output[-1500:]!r}")


def selected(output, title):
    return re.search(r"\x1b\[7;[0-9;]+m[^\x1b]*" + re.escape(title), output) is not None


def launch(*arguments):
    master, slave = os.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 110, 0, 0))
    original = termios.tcgetattr(slave)
    environment = dict(os.environ, TERM="xterm-256color")
    environment.pop("NO_COLOR", None)
    process = subprocess.Popen([str(BINARY), *arguments], stdin=slave, stdout=slave, stderr=slave, env=environment)
    return process, master, slave, original


def finish(process, master, slave, original):
    try:
        if process.poll() is None:
            os.write(master, b"q")
        process.wait(timeout=3)
        assert process.returncode == 0, process.returncode
        restored = termios.tcgetattr(slave)
        restored[3] &= ~termios.PENDIN
        original[3] &= ~termios.PENDIN
        assert restored == original, f"Terminal settings were not restored: {original!r} -> {restored!r}"
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)


with tempfile.TemporaryDirectory(prefix="orca-watch-tests-") as temporary:
    directory = Path(temporary)
    bridge = directory / "bridge"
    payload = directory / "snapshot.json"
    bridge.write_text("#!/usr/bin/env python3\nfrom pathlib import Path\nprint(Path(__file__).with_name('snapshot.json').read_text())\n")
    bridge.chmod(0o700)
    payload.write_text(json.dumps(fixture()))
    process, master, slave, original = launch("--bridge", str(bridge), "--interval", "0.5")
    try:
        wait_for(master, lambda output: selected(output, "Task B"))
        os.write(master, b"G")
        wait_for(master, lambda output: selected(output, "Task A"))
        payload.write_text(json.dumps(fixture("a")))
        output = wait_for(master, lambda output: selected(output, "Task A"))
        assert not selected(output, "Task B"), "Refresh selected the old row's replacement"
        assert re.search(r"\x1b\[6;1H[^\x1b]*\x1b\[2K\x1b\[7;", output), "Selected session did not move up"
        os.write(master, b"h")
        wait_for(master, lambda output: "▸ Alpha" in output)
        os.write(master, b"l")
        wait_for(master, lambda output: "Task A" in output)
        os.write(master, b"/Beta\r")
        output = wait_for(master, lambda output: selected(output, "Task B"))
        os.write(master, b"\x1b")
        wait_for(master, lambda output: "Task A" in output)
        os.kill(process.pid, signal.SIGTERM)
    finally:
        finish(process, master, slave, original)

    slow = directory / "slow"
    slow.write_text("#!/bin/sh\necho $$ > \"$(dirname \"$0\")/child.pid\"\nexec sleep 30\n")
    slow.chmod(0o700)
    process, master, slave, original = launch("--bridge", str(slow))
    try:
        wait_for(master, lambda output: "Connecting" in output)
        deadline = time.monotonic() + 3
        while not (directory / "child.pid").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        child = int((directory / "child.pid").read_text())
    finally:
        finish(process, master, slave, original)
    try:
        os.kill(child, 0)
        raise AssertionError("Quitting left a Bridge child running")
    except ProcessLookupError:
        pass

snapshot = subprocess.run([str(BINARY), "snapshot", "--demo"], check=True, capture_output=True)
assert len(json.loads(snapshot.stdout)["sessions"]) == 5
events = subprocess.run([str(BINARY), "log", "--demo", "--json", "--once"], check=True, capture_output=True)
assert [json.loads(line)["kind"] for line in events.stdout.splitlines()] == ["opened"] * 5
print("Terminal acceptance passed: reorder selection, collapse, filter, signal restoration, child cleanup, snapshot and log.")
