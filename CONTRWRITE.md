# Contrawrite

A personal fork of [Omawrite](https://github.com/omacom-io/omawrite). Same editor, plus:

- Tabs, so one window holds several documents (`Ctrl+T`, `Ctrl+W`, `Ctrl+Tab`)
- The last session's tabs reopen on a plain launch
- 30-second autosave of named files
- Local checkpoints, revert from the footer clock or `Ctrl+Shift+H`

Stock Omawrite stays installed. Super+Shift+W launches Contrawrite.

## Why a fork

Omawrite's pitch is "no vaults, no plugins, just you and the words." Autosave of a named file is close to iA Writer and might land upstream. A checkpoint browser is extra chrome, and that is the part that is unlikely to merge. This fork exists so the feature can track Omawrite without waiting on that.

## Layout

| What | Where |
|---|---|
| Checkout | `~/dev/contrawrite` (`~/dev/omawrite` is a symlink) |
| GitHub | `matt-shearing/contrawrite` (public fork of `omacom-io/omawrite`) |
| Upstream remote | `upstream` → `omacom-io/omawrite` |
| Binary | `~/bin/contrawrite` |
| Checkpoints | `~/.local/share/Omacom/omawrite/history/` (same AppData as Omawrite, so existing snapshots survive) |
| Remembered tabs | `~/.local/share/Omacom/omawrite/contrawrite-session.json` |
| Last sync state | `~/.local/state/contrawrite/` |

The `.pro` target stays `omawrite` on purpose. Fewer conflicts when DHH touches the build file; `bin/install-user` copies `build/omawrite` to `~/bin/contrawrite`.

## How tabs stay mergeable

Tabs had to change Omawrite's main file, `src/Main.qml`, and that file is where
upstream does most of its work. Three choices keep future merges quiet:

- Omawrite's editor block stays in `src/Main.qml`. Tabs wrap it in a page
  component, which indents it further and changes nothing else. `bin/sync` merges
  with `-Xignore-space-change`, so an upstream edit to those lines still merges
  cleanly. A trial merge of upstream PR #71, which rewrites 226 lines of that
  block, went through without a conflict.
- The rest of the window still says `backend`, `editor` and `editorFlick`. Those
  names now mean the current tab's, so the lines that use them did not change.
- The shortcuts help keeps upstream's line exactly as written and adds
  Contrawrite's shortcuts after it. Every upstream pull request that adds a
  shortcut edits that one line, and it used to conflict each time.

Omawrite's own tests pass unchanged. They hand the window one `Backend`, and that
one becomes the first tab's document; `src/FirstBackend.qml` is what passes it
across.

## Tracking upstream

`omarchy update` runs `hooks/post-update-contrawrite.sh`, which execs `bin/sync --from-hook`.

`bin/sync` then:

1. Does nothing if `omawrite`'s pacman version is unchanged **and** `upstream/master` is already an ancestor of `HEAD`.
2. Otherwise fetches `upstream`, merges `upstream/master` with `-Xignore-space-change`, builds, tests, and installs.
3. If the merge conflicts or tests fail, it opens a floating terminal running Grok Build with `hooks/sync-prompt.md` and leaves the tree for the agent to finish.

Run it by hand:

```bash
~/dev/contrawrite/bin/sync            # merge + build if needed
~/dev/contrawrite/bin/sync --status   # print versions / SHAs
~/dev/contrawrite/bin/sync --with-grok
```

Do not open a PR against `omacom-io/omawrite` from this branch.
