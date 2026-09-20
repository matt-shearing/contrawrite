# Contrawrite

A personal fork of [Omawrite](https://github.com/omacom-io/omawrite): the same
dead-simple Markdown writer, with tabs, 30-second autosave and local checkpoints.

On this machine Super+Shift+W launches Contrawrite. Stock Omawrite stays
installed as its own app.

How the fork tracks upstream, where files live, and what the post-update hook
does: **[CONTRWRITE.md](CONTRWRITE.md)**.

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
- `Ctrl+B`, `Ctrl+I`, and `Ctrl+K` insert bold, italic, and link Markdown.
- `Ctrl+?` shows the keyboard shortcut reference.

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

Named files autosave every 30 seconds while they have unsaved edits. Each autosave
and manual save keeps a local checkpoint; the clock icon in the footer (or
`Ctrl+Shift+H`) reverts to any of them. Untitled windows are checkpointed the same
way until the first Save As.

Unsaved drafts are recovered after an abnormal exit, one tab for each draft.
Contrawrite also watches every open file and warns before an external change can
replace local work. If several open files change together, as they do after a
sync or a `git checkout`, it asks about them one at a time and shows each file's
tab while it asks.

Text follows the desktop text size — `omarchy display text size`, or GNOME's
`text-scaling-factor` — and re-flows without a restart. The default of 12px leaves
the editor at the size Omawrite is designed around; larger and smaller sizes scale from there.

## Requirements

- Qt 6: `qt6-base`, `qt6-declarative`, `qt6-quickcontrols2`
- `xdg-desktop-portal` and a portal backend

The iA Writer Mono font is bundled under the SIL Open Font License 1.1; see
`fonts/OFL.txt`. The font is copyright Information Architects Inc. and based on
IBM Plex, copyright IBM Corp.
