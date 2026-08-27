# Contrawrite

A personal fork of [Omawrite](https://github.com/omacom-io/omawrite). Same editor, plus:

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
| Last sync state | `~/.local/state/contrawrite/` |

The `.pro` target stays `omawrite` on purpose. Fewer conflicts when DHH touches the build file; `bin/install-user` copies `build/omawrite` to `~/bin/contrawrite`.

## Tracking upstream

`omarchy update` runs `hooks/post-update-contrawrite.sh`, which execs `bin/sync --from-hook`.

`bin/sync` then:

1. Does nothing if `omawrite`'s pacman version is unchanged **and** `upstream/master` is already an ancestor of `HEAD`.
2. Otherwise fetches `upstream`, merges `upstream/master`, builds, tests, and installs.
3. If the merge conflicts or tests fail, it opens a floating terminal running Grok Build with `hooks/sync-prompt.md` and leaves the tree for the agent to finish.

Run it by hand:

```bash
~/dev/contrawrite/bin/sync            # merge + build if needed
~/dev/contrawrite/bin/sync --status   # print versions / SHAs
~/dev/contrawrite/bin/sync --with-grok
```

Do not open a PR against `omacom-io/omawrite` from this branch.
