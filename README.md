# Contrawrite

A personal fork of [Omawrite](https://github.com/omacom-io/omawrite): the same
dead-simple Markdown writer, with tabs that come back the next time you launch it,
autosave and local checkpoints.

On this machine Super+Shift+W launches Contrawrite. Stock Omawrite stays
installed as its own app.

How the fork tracks upstream, where files live, and what the post-update hook
does: **[CONTRWRITE.md](CONTRWRITE.md)**.

## Command line

`omawrite` opens an empty document and `omawrite FILE` opens a Markdown file.
`omawrite --help` answers in the terminal without opening a window.

## Shortcuts

- `Ctrl+S` saves. Unsaved documents use the XDG desktop portal file picker.
- `Ctrl+Shift+S` saves as.
- `Ctrl+O` opens a Markdown file through the portal picker.
- `Ctrl+P` opens the system print dialog.
- `Ctrl+N` opens a new Contrawrite window.
- `Ctrl+T` opens a new tab and `Ctrl+W` closes the current one.
- `Ctrl+Tab` and `Ctrl+Shift+Tab` move to the next and previous tab. `Ctrl+PgDown` and `Ctrl+PgUp` do the same.
- `Alt+1` to `Alt+9` jump to a tab by its position.
- `Ctrl+Z`, `Ctrl+Shift+Z`, and `Ctrl+Y` handle undo and redo.
- `Super+F` toggles fullscreen. Qt maps this key as `Meta+F`.
- `Ctrl+F` searches the document. Use `Enter` or `Ctrl+G` for the next match and `Shift+Enter` for the previous match.
- `Ctrl+H` opens find and replace.
- `Ctrl+Shift+H` opens checkpoints.
- `Ctrl+B`, `Ctrl+I`, and `Ctrl+Shift+X` toggle bold, italic, and strikethrough Markdown. `Ctrl+K` inserts a link.
- `Ctrl+=` and `Ctrl+-` change the text size, `Ctrl+0` returns to the default.
  `Ctrl+scroll` does the same.
- `Ctrl+Shift+C` copies the rendered document as HTML, with plain text as a fallback.
- `Ctrl+?`, `Ctrl+/`, or `F1` shows the keyboard shortcut reference.
- In the unsaved-changes dialog, `C`, `D`, and `S` choose Cancel, Discard, and Save, with or without `Alt`. `Escape` cancels.

One window holds several documents, each in its own tab. The row of tabs appears
once a second document is open, so a window with one file looks the same as
Omawrite. Opening a file gives it a new tab, unless the current tab is blank, in
which case the file loads there. A file that is already open is brought to the
front instead of being opened twice. When two tabs share a file name, such as two
projects that each have a `README.md`, the tab shows the folder as well. A tab
with no file yet is named after its first line. Click the `+` to add a tab, and
click a tab's `×` or middle-click the tab to close it. Every file named on the
command line gets a tab.

Each tab keeps its own undo history, cursor, scroll position, autosave and
checkpoints. Closing a tab with unsaved changes asks what to do with them, and
closing the window asks about each unsaved tab in turn. Closing the last tab
closes the window.

Launched on its own, Contrawrite reopens the files that were in its tabs last
time, in the same order, with the same tab in front. It writes the list down
whenever the tabs change, so the tabs also come back after a crash or a power cut.
A file that has since been moved or deleted is left out. A tab you close on
purpose stays closed.

One window at a time remembers its tabs: the first one launched on its own. While
it is running, a second launch starts blank, because two windows holding the same
files would autosave over each other. A window opened for a particular file, from
the file manager or as `contrawrite notes.md`, shows that file alone, and
`Ctrl+N` always gives a blank window. Neither changes the remembered tabs.

Once a document has been saved to a file, edits are auto-saved to that file a
moment after you stop typing, so `Ctrl+S` is rarely needed. Each of those saves,
and each manual save, keeps a local checkpoint; the clock icon in the footer (or
`Ctrl+Shift+H`) reverts to any of them. Auto-save pauses when the file changes
elsewhere, or when saving would rewrite its encoding or line endings, until you
reload, keep your version, or save. A recovered draft is never auto-saved over
its file — save it to keep it. An untitled document is never written to a file
on its own; Contrawrite checkpoints it every 30 seconds until the first Save As.

Unsaved drafts are recovered after an abnormal exit, one tab for each draft.
Contrawrite also watches every open file and warns before an external change can
replace local work. If several open files change together, as they do after a
sync or a `git checkout`, it asks about them one at a time and shows each file's
tab while it asks.

The font button in the footer picks the writing font from any installed text font,
and the choice is remembered. IBM Plex Mono is the default.

Text follows the desktop text size — `omarchy display text size`, or GNOME's
`text-scaling-factor` — and re-flows without a restart. The default of 12px leaves
the editor at the size Omawrite is designed around; larger and smaller sizes scale
from there. `Ctrl+=`, `Ctrl+-`, and `Ctrl+scroll` set your own size on top of that,
from 50% to 300% in browser-sized steps. It is remembered for the next window you open.

Omawrite speaks the language picked under Omarchy's Setup > Language and switches with it, without a restart. Right-to-left languages mirror the window. The translations live in `src/i18n/`, one JSON file per language keyed by the English text, and `src/i18n/en.json` lists every string to translate.

## Requirements

- Qt 6: `qt6-base` and `qt6-declarative` (which includes Qt Quick Controls)
- `xdg-desktop-portal` and a portal backend

The IBM Plex Mono font is bundled under the SIL Open Font License 1.1; see
`fonts/OFL.txt`. The font is copyright IBM Corp.

## Build

For a local build, install the Qt requirements above, a C++17 compiler such as `gcc`, `cmake`, and `make`. `bin/build` configures and builds into `build/`, and `bin/test` builds and runs the Qt test suite through `ctest`.

```sh
./bin/test
./build/omawrite
```

`bin/test` runs the Qt test suite with the offscreen platform, so it does not
require an active graphical session. To open a file with the local build:

```sh
./build/omawrite path/to/document.md
```
