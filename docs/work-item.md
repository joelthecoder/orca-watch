# Orca Watch

## Spec

Build a private Swift project at `joelthecoder/orca-watch`, with a native macOS desktop widget and live terminal dashboard. All Orca reads and navigation go through the installed `orca-bridge` CLI. No menu bar app.

Acceptance:

- Open agents sort by last observed activity descending. Projects sort by their newest session; ties use stable IDs.
- Selection follows session identity when sorting changes. Projects collapse, retain stable colors, and support Vim movement and arrows.
- Provide a full-screen terminal, JSON snapshots and a change log for pipes.
- A containing app collects Bridge snapshots into an App Group cache. Small, medium and large WidgetKit widgets show recent sessions and freshness.
- Unknown states and outages remain visible. Never infer live ownership from titles or paths. Keep transcripts, caches and credentials out of Git.
- Deliver reproducible app and project icons, register the project and apply its icon through Bridge.
- Execute behavioral tests, CLI smoke checks and an Xcode app/extension build before committing and publishing.

Decisions: macOS 14+, Swift Package core/CLI, XcodeGen helper/extension. ANSI terminal without ncurses. Poll snapshots every two seconds. WidgetKit refresh follows macOS scheduling. The required containing app bundle is invisible: no window, Dock icon or menu bar item. Widget session clicks focus Orca through Bridge after a fresh identity check. The initial visible dashboard was removed after Joel clarified that only the CLI and widget are wanted.

## Foundation

1. Bridge owns compatibility and credentials. Its `agent` and `schema snapshot` commands expose versioned normalized data.
2. Bridge's local `docs/ui-data.md` describes runtime-fenced snapshots and independent resource availability.
3. Session IDs are durable. Terminal handles expire across incarnations. Selection uses session IDs or incarnation-qualified terminal identity for unindexed agents.
4. Folder matches associate metadata only. Missing bindings do not prove idle or closed. Outages preserve the last known display with stale labeling.
5. One projection and navigation model keeps sorting, liveness and selection behavior consistent and testable across surfaces.

Swift LSP navigation is not exposed by this tool interface. Contracts were inspected through CLI schemas and local prose documentation.

## Plan

1. Implement decoding, projection, identity navigation, bounded subprocess execution and synthetic behavioral tests.
2. Build live ANSI dashboard, snapshot and log commands; smoke against Bridge without committing live content.
3. Add SwiftUI containing app, shared cache and WidgetKit extension; build and verify the shared data path.
4. Create and inspect identity assets, apply project icon, document installation and limits.
5. Review, run `make check`, commit verified slices and publish the initial private repository.

## Tasks

- [x] Core and behavioral tests
- [x] CLI and live smoke
- [x] App and widget build
- [x] Artwork and Orca icon
- [x] Documentation and local review
- [ ] Initial private publication

## Evidence

- `make check`: synthetic core tests, formatting, warnings-as-errors build and terminal acceptance executed successfully.
- PTY acceptance: a selected session moved between project positions and remained selected; collapse/expand, filtering, signal restoration, stalled-child cleanup, JSON snapshot and JSONL log verified.
- Signal test initially compared macOS's kernel-maintained PENDIN flag. An isolated Python raw/restore round trip reproduced the same flag; the assertion now masks that flag and compares every user setting.
- Live CLI snapshot returned 26 open agents across 9 projects at the first smoke check. No live payload is committed.
- Unsigned and Apple Development signed app/extension builds succeeded. Deep strict code-signature verification passed for the installed app.
- Shared cache read-back confirmed live sessions and 0600 permissions. PlugInKit lists the extension. The final invisible helper passes CLI start, stop and status checks and is absent from the regular-app inventory. Desktop placement is a user choice through Edit Widgets; actual desktop WidgetKit rendering and refresh scheduling remain system-controlled.
- Small, medium and large shared widget cards were rendered and visually inspected. The first medium render overflowed vertically; its compact layout now fits three rows.
- SVG semantic validation passed. Identity concepts were compared as surfacing signal, eye and monogram; surfacing signal was selected for its orca-specific silhouette. Export and visual checks cover the master and small icon sizes.
- Orca project PNG applied through Bridge with an acknowledged `applied: true` result. Display name and badge color were read back after their narrow settings patch.
- Native deep-link retry brought this task's exact live session into focus in Orca, verified in the Orca window. URL parsing also has synthetic round-trip and malformed-route coverage.
- General Swift code review covered liveness evidence, selection, process cancellation, shared cache, URL handling and helper lifecycle. No repository-specific Rails review skill exists in this new Swift repository.
