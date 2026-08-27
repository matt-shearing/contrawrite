# Contrawrite

A personal fork of [Omawrite](https://github.com/omacom-io/omawrite): the same
dead-simple Markdown writer, with 30-second autosave and local checkpoints.

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
- `Ctrl+Z`, `Ctrl+Shift+Z`, and `Ctrl+Y` handle undo and redo.
- `Super+F` toggles fullscreen. Qt maps this key as `Meta+F`.
- `Ctrl+F` searches the document. Use `Enter` or `Ctrl+G` for the next match and `Shift+Enter` for the previous match.
- `Ctrl+H` opens find and replace.
- `Ctrl+Shift+H` opens checkpoints.
- `Ctrl+B`, `Ctrl+I`, and `Ctrl+K` insert bold, italic, and link Markdown.
- `Ctrl+?` shows the keyboard shortcut reference.

Named files autosave every 30 seconds while they have unsaved edits. Each autosave
and manual save keeps a local checkpoint; the clock icon in the footer (or
`Ctrl+Shift+H`) reverts to any of them. Untitled windows are checkpointed the same
way until the first Save As.

Unsaved drafts are recovered after an abnormal exit. Contrawrite also watches open files
and warns before an external change can replace local work.

Text follows the desktop text size — `omarchy display text size`, or GNOME's
`text-scaling-factor` — and re-flows without a restart. The default of 12px leaves
the editor at the size Omawrite is designed around; larger and smaller sizes scale from there.

## Requirements

- Qt 6: `qt6-base`, `qt6-declarative`, `qt6-quickcontrols2`
- `xdg-desktop-portal` and a portal backend

The iA Writer Mono font is bundled under the SIL Open Font License 1.1; see
`fonts/OFL.txt`. The font is copyright Information Architects Inc. and based on
IBM Plex, copyright IBM Corp.
