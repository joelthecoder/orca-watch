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
        tabs.append({"id": name, "terminal": name, "incarnationId": name, "worktreeId": project,
                     "agentStatus": {"state": "working" if name == newest else "waiting"}})
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
        if predicate(output) and output.endswith("\x1b[1;1H"):
            return output
    raise AssertionError(f"Terminal condition timed out: {output[-1500:]!r}")


def selected(output, title):
    return re.search(r"\x1b\[[0-9;]*48;5;24m[^\x1b]*" + re.escape(title), output) is not None


def selected_at(output, title, row):
    line = re.search(r"\x1b\[" + str(row) + r";1H\x1b\[2K(.*?)(?=\x1b\[\d+;1H|$)", output, re.S)
    return line is not None and selected(line.group(1), title)


def assert_cursor_parked(output):
    assert output.endswith("\x1b[1;1H"), "Redraw left the hidden cursor on a changing row"


def assert_paint_bounds(output, width, height):
    positions = re.findall(r"\x1b\[(\d+);(\d+)H", output)
    assert positions, "No positioned output found"
    assert all(1 <= int(row) <= height and 1 <= int(column) <= width for row, column in positions), positions
    for line in re.findall(r"\x1b\[2K(.*?)(?=\x1b\[\d+;\d+H|$)", output, re.S):
        plain = re.sub(r"\x1b\[[0-9;]*m", "", line)
        assert len(plain) < width, f"Redraw exceeded the safe terminal width: {plain!r}"


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
        deadline = time.monotonic() + 3
        while process.poll() is None and time.monotonic() < deadline:
            drain(master, 0.05)
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
    bridge.write_text("""#!/usr/bin/env python3
import sys
import time
from pathlib import Path
root = Path(__file__).parent
if sys.argv[1:3] == ['terminals', 'focus']:
    (root / 'focus-started').touch()
    if (root / 'focus-delay').exists():
        time.sleep(float((root / 'focus-delay').read_text()))
    (root / 'focused').write_text(sys.argv[3])
    print('{}')
else:
    with (root / 'request-starts').open('a') as starts:
        starts.write(str(time.monotonic()) + '\\n')
    if (root / 'snapshot-delay').exists():
        time.sleep(float((root / 'snapshot-delay').read_text()))
    print((root / 'snapshot.json').read_text())
""")
    bridge.chmod(0o700)
    payload.write_text(json.dumps(fixture()))
    process, master, slave, original = launch("--bridge", str(bridge), "--interval", "0.5")
    try:
        initial = wait_for(master, lambda output: selected(output, "Task A"))
        assert_cursor_parked(initial)
        for column in ["SESSION", "STATE", "AGENT", "PROJECT", "BRANCH", "AGE"]:
            assert column in initial, f"Missing table column: {column}"
        os.write(master, b"G")
        wait_for(master, lambda output: selected(output, "Task B"))
        payload.write_text(json.dumps(fixture("a")))
        output = wait_for(master, lambda output: selected_at(output, "Task B", 9))
        assert not selected(output, "Task A"), "Refresh selected the old row's replacement"
        assert_cursor_parked(output)
        os.write(master, b"gj")
        wait_for(master, lambda output: selected(output, "Task A"))
        os.write(master, b"h")
        wait_for(master, lambda output: "▸ Alpha" in output)
        os.write(master, b"l")
        wait_for(master, lambda output: "Task A" in output)
        os.write(master, b"/Beta\r")
        output = wait_for(master, lambda output: selected(output, "Task B"))
        os.write(master, b"\x1b")
        wait_for(master, lambda output: "Task A" in output)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 16, 60, 0, 0))
        os.kill(process.pid, signal.SIGWINCH)
        resized = wait_for(master, lambda output: "SESSION" in output and "AGE" in output)
        assert "MODEL" not in resized and "BRANCH" not in resized, "Secondary columns did not adapt"
        os.write(master, b"g")
        wait_for(master, lambda output: selected(output, "▾ Alpha"))
        os.write(master, b"\x04")
        wait_for(master, lambda output: selected(output, "Task B"))
        os.write(master, b"\x15")
        wait_for(master, lambda output: selected(output, "▾ Alpha"))
        os.write(master, b"\x1b[6~")
        wait_for(master, lambda output: selected(output, "Task B"))
        os.write(master, b"gj\r")
        deadline = time.monotonic() + 3
        while not (directory / "focused").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        assert (directory / "focused").read_text() == "a", "Focus used the selection from before this input batch"
        drain(master)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 4, 12, 0, 0))
        os.kill(process.pid, signal.SIGWINCH)
        tiny = wait_for(master, lambda output: "ORCA" in output)
        assert_paint_bounds(tiny, width=12, height=4)
        assert_cursor_parked(tiny)
        os.kill(process.pid, signal.SIGTERM)
    finally:
        finish(process, master, slave, original)

    (directory / "focus-started").unlink(missing_ok=True)
    (directory / "focus-delay").write_text("1.5")
    process, master, slave, original = launch("--bridge", str(bridge))
    try:
        initial = wait_for(master, lambda output: selected(output, "Task A"))
        os.write(master, b"\r")
        deadline = time.monotonic() + 2
        while not (directory / "focus-started").exists() and time.monotonic() < deadline:
            drain(master, 0.01)
        assert (directory / "focus-started").exists(), "Focus did not start"
        started = time.monotonic()
        os.write(master, b"G")
        wait_for(master, lambda output: selected(output, "Task B"), timeout=0.4)
        assert time.monotonic() - started < 0.4, "Slow Bridge focus blocked navigation"
        assert "5s" in initial, "Default polling interval did not reduce background work"
    finally:
        finish(process, master, slave, original)
        (directory / "focus-delay").unlink()

    (directory / "request-starts").unlink(missing_ok=True)
    (directory / "snapshot-delay").write_text("0.8")
    process, master, slave, original = launch("--bridge", str(bridge), "--interval", "0.5")
    try:
        wait_for(master, lambda output: selected(output, "Task A"))
        deadline = time.monotonic() + 3
        starts = []
        while len(starts) < 2 and time.monotonic() < deadline:
            drain(master, 0.05)
            starts = [float(value) for value in (directory / "request-starts").read_text().splitlines()]
        assert len(starts) >= 2, "Second snapshot did not start"
        assert starts[1] - starts[0] >= 1.2, "Slow snapshots caused back-to-back polling"
    finally:
        finish(process, master, slave, original)
        (directory / "snapshot-delay").unlink()

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
print("Terminal acceptance passed: table columns, stable projects, selection, collapse, filter, resize, tiny bounds, parked cursor, paging, exact focus, responsive slow focus, spaced slow polls, signal restoration, child cleanup, snapshot and log.")
