Update Contrawrite so it tracks the latest Omawrite, then ship a working install.

Checkout: $HOME/dev/contrawrite (symlink: $HOME/dev/omawrite)
Remotes: origin = matt-shearing/contrawrite, upstream = omacom-io/omawrite
Do not push to upstream. Do not open a PR against omacom-io/omawrite.

Contrawrite is Omawrite plus only this product delta:

1. 30-second autosave of named files, local checkpoints, footer clock / Ctrl+Shift+H to revert. Code lives mainly in src/backend.cpp, src/backend.h, src/Main.qml, src/FooterIconButton.qml, src/HistoryPopup.qml, src/resources.qrc, tests/tst_omawrite.cpp.
2. Tabs: several documents in one window. Every tab is a page with its own Backend, Flickable and TextEdit. In src/Main.qml, Omawrite's editor Flickable sits inside `Component { id: pageComponent }`, re-indented and otherwise as upstream wrote it, so upstream edits to the editor belong inside that component. The window's `backend`, `editor` and `editorFlick` properties point at the current tab and hide the `backend` context property; src/FirstBackend.qml (a singleton, declared in src/qmldir) hands that context backend to the first tab. Backend::createSibling, closeDocument and hasOrphanedRecovery serve the tabs. Tab strip: src/TabStrip.qml. The shortcuts help keeps upstream's `text:` line untouched and appends Contrawrite's shortcuts in Component.onCompleted.
3. User-visible name Contrawrite (window title, desktop file, ~/bin/contrawrite). Keep QApplication organization Omacom and applicationName omawrite so checkpoints stay in ~/.local/share/Omacom/omawrite/.
4. Tracking scripts: CONTRWRITE.md, bin/sync, bin/sync-with-grok, bin/install-user, hooks/. The .pro target stays `omawrite`; install-user copies build/omawrite to ~/bin/contrawrite.

What to do:

- If the tree has a merge in progress or conflict markers, finish that merge. Otherwise fetch upstream and merge with `git merge -Xignore-space-change upstream/master`; the flag matters because tabs re-indent the editor block.
- Keep the Contrawrite delta. When Omawrite and Contrawrite both edited the same lines, prefer a result that still autosaves, checkpoints, reverts, and keeps every tab's document separate. A closed tab must never write to disk again (Backend::closeDocument).
- Run ./bin/test. Fix failures caused by the merge.
- Run ./bin/install-user.
- Commit any merge or fix (conventional subject, no Co-Authored-By). Push origin HEAD. Do not force-push.
- Write last-sync state to ~/.local/state/contrawrite/ (omawrite-pkg from `pacman -Q omawrite`, upstream-sha from `git rev-parse upstream/master`).

Stay inside that scope. If upstream cannot be merged without destroying autosave, checkpoints or tabs, stop, leave the tree as-is, and say why.
