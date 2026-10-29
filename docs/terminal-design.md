# Terminal table redesign

## Spec

Replace the loose activity list with a full-width terminal table. Preserve Bridge-only reads, identity-based selection, project folding, filters, live refresh and focus actions. This change affects the CLI only; the desktop widget keeps its current design.

Acceptance:

- Aligned session, state, agent, project, branch, model and age columns, with secondary columns removed as width decreases.
- The session column receives remaining width instead of leaving a large unused right side.
- Full-row selection, project-colored rails, semantic status colors, compact top bars, a selected-session detail strip and bottom key hints.
- Table rows never wrap or exceed available terminal cells. Unicode and resized terminals retain alignment.
- Refresh, fold and filtering preserve the existing identity invariants. Empty, disconnected, paused and filtered states have explicit treatment.
- Execute layout tests, terminal acceptance at multiple sizes, and inspect an actual rendered terminal capture before installation and commit.

## Foundation

1. The existing renderer exists to show the shared live projection without blocking input. `main.swift` currently concatenates all fields into a single string.
2. That shape made the first iteration simple, but the early title controls where every subsequent field appears, preventing comparison across rows.
3. `NavigationState` already owns stable selection and folding. Rendering must consume it rather than recreate identity or ordering rules.
4. Terminal painting updates only changed lines. A pure layout can retain that behavior, while bounding each row by display cells rather than string length.
5. Extract the screen layout from the CLI loop so width, alignment and selection can be checked independently of Bridge and a running terminal.

Swift LSP navigation is not exposed in the current tool interface. Source inspection uses direct reads, followed by compiler diagnostics and executed behavior checks.

## References

Read-only `reddit-cli` searches in r/unixporn: `btop terminal` and `tui terminal`, top sort, year window, one page of six results each. Both searches retain next-page cursors; coverage is partial. No comments were expanded.

- [Yabai: My first macOS rice](https://www.reddit.com/r/unixporn/comments/1ri0wuk/yabai_my_first_macos_rice/): 953 points, 47 comments, posted 2026-03-01 in the CLI result. Inspected gallery media for restrained dark surfaces and cool accents.
- [Surge terminal download manager](https://www.reddit.com/r/unixporn/comments/1qzfd79/i_built_surge_a_foss_download_manager_that_beats/): 1177 points, 143 comments, posted 2026-02-08 in the CLI result. Inspected settings and main-view media for thin separators and clear keyboard affordances.
- [tig repository](https://github.com/jonas/tig) and [manual](https://jonas.github.io/tig/doc/manual.html): aligned summaries, a selected identity tied to the cursor, and a bottom status window. Also captured the installed default tig view against this repository without user configuration.

The chosen direction uses tig's density and alignment, plus muted panel borders and status accents. It does not copy artwork, code or a desktop rice.

## Plan

1. Add pure cell-aware terminal layout, responsive column allocation and screen rendering.
2. Connect the CLI loop, retain differential painting and add familiar page movement.
3. Update acceptance checks and docs; inspect wide, narrow and empty terminal captures.
4. Run checks, install the CLI and commit the verified change locally. This redesign does not authorize another remote push.

## Tasks

- [x] Table renderer and responsive layout
- [x] CLI integration and keyboard checks
- [x] Visual inspection, installation and verification

## Verification

- `make check` passed: seven terminal-layout tests, thirteen existing core tests, formatting, warnings-as-errors compilation and PTY acceptance.
- Layout checks cover widths 1 through 219 at representative sizes, with and without color, short terminals, Unicode cell widths and a selected session moving between positions.
- PTY acceptance verifies aligned column labels, selection through reorder, folding, filtering, live resize, half-page and full-page keys, exact focus, terminal restoration and child cleanup.
- Actual CLI captures were inspected at 140, 80 and 40 columns. The wide and medium captures use synthetic demo data. No Reddit artwork or live session content is checked in.
- `make app` passed after the package target addition. `make install` built and installed the release CLI.

The keyboard test found an existing focus bug: a rapid `g`, `j`, Enter batch could focus the session selected before the batch. The selected session was cached above the key loop; terminal input can deliver several keys per read; focus used that cached render identity; navigation could therefore advance without updating the action target. Focus now resolves the current selection inside the Enter handler. The new PTY assertion failed before the fix and passes after it.
