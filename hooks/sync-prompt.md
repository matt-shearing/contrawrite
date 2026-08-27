Update Contrawrite so it tracks the latest Omawrite, then ship a working install.

Checkout: $HOME/dev/contrawrite (symlink: $HOME/dev/omawrite)
Remotes: origin = matt-shearing/contrawrite, upstream = omacom-io/omawrite
Do not push to upstream. Do not open a PR against omacom-io/omawrite.

Contrawrite is Omawrite plus only this product delta:

1. 30-second autosave of named files, local checkpoints, footer clock / Ctrl+Shift+H to revert. Code lives mainly in src/backend.cpp, src/backend.h, src/Main.qml, src/FooterIconButton.qml, src/HistoryPopup.qml, src/resources.qrc, tests/tst_omawrite.cpp.
2. User-visible name Contrawrite (window title, desktop file, ~/bin/contrawrite). Keep QApplication organization Omacom and applicationName omawrite so checkpoints stay in ~/.local/share/Omacom/omawrite/.
3. Tracking scripts: CONTRWRITE.md, bin/sync, bin/sync-with-grok, bin/install-user, hooks/. The .pro target stays `omawrite`; install-user copies build/omawrite to ~/bin/contrawrite.

What to do:

- If the tree has a merge in progress or conflict markers, finish that merge. Otherwise fetch upstream and merge upstream/master into HEAD.
- Keep the Contrawrite delta. When Omawrite and Contrawrite both edited the same lines, prefer a result that still autosaves, checkpoints, and reverts.
- Run ./bin/test. Fix failures caused by the merge.
- Run ./bin/install-user.
- Commit any merge or fix (conventional subject, no Co-Authored-By). Push origin HEAD. Do not force-push.
- Write last-sync state to ~/.local/state/contrawrite/ (omawrite-pkg from `pacman -Q omawrite`, upstream-sha from `git rev-parse upstream/master`).

Stay inside that scope. If upstream cannot be merged without destroying autosave/checkpoints, stop, leave the tree as-is, and say why.
