import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import QtQuick.Window
import QtQml.Models
import "."
import "EditorMutations.js" as EditorMutations

ApplicationWindow {
    id: win
    width: 1280
    height: 820
    minimumWidth: 720
    minimumHeight: 520
    visible: true
    title: (backend.modified ? "* " : "") + backend.fileName + " - Contrawrite"

    readonly property bool darkMode: backend.darkMode
    readonly property color pageColor: backend.themeBackground
    readonly property color textColor: backend.themeForeground
    readonly property color mutedColor: darkMode ? "#909191" : "#aeb1b5"
    readonly property color selectionFill: backend.themeSelection
    readonly property color selectionTextColor: backend.themeSelectionForeground
    // The desktop's text size knob (GNOME's text-scaling-factor, which
    // `omarchy display text size` drives) anchored so its 12px default leaves
    // the app at the sizes it was designed around, times the user's own
    // text size set with Ctrl+= / Ctrl+- / Ctrl+wheel.
    readonly property real textScale: backend.textScale
    readonly property int editorFontPixelSize: scaledSize(20)
    readonly property int footerHeight: scaledSize(32)
    // Never wider than the Flickable's viewport, whatever the floor asks for:
    // a tiling compositor can resize the window below its minimum width.
    readonly property int editorWidth: Math.min(
        Math.round(writerFontMetrics.averageCharacterWidth * 65),
        Math.max(360, width - Math.round(writerFontMetrics.averageCharacterWidth * 20)),
        Math.max(0, width - 48))
    property bool closeConfirmed: false
    property bool searchOpen: false
    property bool searchUpdating: false
    property var searchMatches: []
    property int searchMatchIndex: -1
    property string pendingAction: ""
    property bool replaceOpen: false
    property bool awaitingPendingSave: false

    // Tabs. `backend`, `editor` and `editorFlick` always mean the current tab's,
    // so whatever in this window acts on "the document" needs no tab logic of
    // its own. This `backend` hides the context property of the same name;
    // FirstBackend is how the first tab still gets hold of that one.
    property var pages: []
    property Item currentPage: null
    readonly property var backend: currentPage ? currentPage.backend : FirstBackend.instance
    readonly property Item editor: currentPage ? currentPage.editorItem : null
    readonly property Item editorFlick: currentPage ? currentPage.flickItem : null
    readonly property int tabCount: pages.length
    readonly property int currentIndex: pages.indexOf(currentPage)
    // While a question about one tab is on screen, or its answer is still being
    // carried out, the tabs hold still. Kept by hand: a dialog's own `opened`
    // is false for as long as it is animating in or out.
    property bool askingUnsaved: false
    property bool askingExternal: false
    readonly property bool tabsLocked: askingUnsaved || askingExternal || awaitingPendingSave
    property var externalChanges: []

    // Session. The window that owns it (see restoreSession) writes down which
    // files are in its tabs whenever that changes, so a crash forgets nothing.
    property bool ownsSession: false
    readonly property var sessionFiles: {
        var files = [];
        for (var i = 0; i < pages.length; ++i) {
            if (pages[i].backend.fileUrl.toString() !== "")
                files.push(pages[i].backend.fileUrl.toString());
        }
        return files;
    }
    // Closing the window removes each tab whose edits are discarded. Those
    // files lost their edits, not their place in the session.
    property bool closingWindow: false
    property bool completingAction: false
    property var closeOrder: []
    property string closeCurrent: ""
    property var discardedOnClose: []

    onSessionFilesChanged: saveSession()
    onCurrentPageChanged: saveSession()
    onPendingActionChanged: {
        // Cleared by anything but a completed answer, the close was called off.
        if (pendingAction === "" && !completingAction && closingWindow) {
            closingWindow = false;
            discardedOnClose = [];
            saveSession();
        }
    }

    Material.theme: darkMode ? Material.Dark : Material.Light
    Material.accent: backend.themeAccent
    color: pageColor

    onClosing: function(close) {
        if (closeConfirmed)
            return;

        var unsaved = firstUnsavedPage();
        if (!unsaved)
            return;

        close.accepted = false;
        if (askingExternal)
            return;

        if (!closingWindow) {
            closingWindow = true;
            closeOrder = sessionFiles.slice();
            // Asking about unsaved tabs moves between them; the tab to come
            // back to is the one in use when the close began.
            closeCurrent = currentPage.backend.fileUrl.toString();
            discardedOnClose = [];
        }

        // Already asking about a tab: carry on closing once that is answered.
        if (askingUnsaved || awaitingPendingSave) {
            pendingAction = "close";
            return;
        }
        activatePage(unsaved);
        askUnsaved("close");
    }

    function askUnsaved(action) {
        pendingAction = action;
        askingUnsaved = true;
        unsavedChangesDialog.open();
    }

    function firstUnsavedPage() {
        for (var i = 0; i < pages.length; ++i) {
            if (pages[i].backend.modified)
                return pages[i];
        }
        return null;
    }

    function pageForUrl(url) {
        for (var i = 0; i < pages.length; ++i) {
            if (pages[i].backend.fileUrl.toString() === url.toString())
                return pages[i];
        }
        return null;
    }

    function documentAt(index) {
        return index >= 0 && index < pages.length ? pages[index].backend : null;
    }

    function tabTitle(index) {
        return index >= 0 && index < pages.length ? tabStrip.titleFor(pages[index]) : "";
    }

    function addPage(document) {
        var page = pageComponent.createObject(pageHost, { backend: document });
        pages = pages.concat([page]);
        activatePage(page);
        return page;
    }

    function newTab() {
        if (tabsLocked)
            return null;
        return addPage(FirstBackend.instance.createSibling());
    }

    function activatePage(page) {
        if (!page || page === currentPage)
            return;
        // The search highlight lives in the tab being left; clear it there.
        if (searchOpen)
            closeSearch();
        currentPage = page;
        page.editorItem.forceActiveFocus();
    }

    function activateTab(index) {
        if (!tabsLocked && index >= 0 && index < pages.length)
            activatePage(pages[index]);
    }

    function cycleTab(direction) {
        if (pages.length > 1)
            activateTab((currentIndex + direction + pages.length) % pages.length);
    }

    function closeTab(index) {
        if (tabsLocked || index < 0 || index >= pages.length)
            return;

        var page = pages[index];
        if (!page.backend.modified) {
            removePage(page);
            return;
        }
        // The dialog names, saves and discards the current document.
        activatePage(page);
        askUnsaved("closeTab");
    }

    function removePage(page) {
        var index = pages.indexOf(page);
        if (index < 0)
            return;

        // The last tab takes the window with it.
        if (pages.length === 1) {
            closeConfirmed = true;
            close();
            return;
        }

        var remaining = pages.filter(function(other) { return other !== page; });
        if (page === currentPage) {
            if (searchOpen)
                closeSearch();
            currentPage = remaining[Math.min(index, remaining.length - 1)];
        }
        pages = remaining;
        page.backend.closeDocument();
        page.destroy();
        currentPage.editorItem.forceActiveFocus();
    }

    function requestOpen(url) {
        var alreadyOpen = pageForUrl(url);
        if (alreadyOpen) {
            activateTab(pages.indexOf(alreadyOpen));
            return;
        }
        if (tabsLocked)
            return;

        var page = currentPage && currentPage.pristine ? currentPage : newTab();
        page.backend.open(url);
    }

    function completePendingAction(discarded) {
        var action = pendingAction;
        completingAction = true;
        pendingAction = "";
        completingAction = false;
        if (action === "closeTab") {
            removePage(currentPage);
        } else if (action === "close") {
            // A discarded document is still modified, so its tab has to go
            // before closing again, which then asks about the next unsaved tab.
            if (discarded) {
                if (backend.fileUrl.toString() !== "")
                    discardedOnClose = discardedOnClose.concat([backend.fileUrl.toString()]);
                removePage(currentPage);
            }
            if (!closeConfirmed)
                close();
        }
    }

    // Called by main() for a window launched on its own. Whichever window
    // claims the session first reopens last time's files and owns the list
    // until it exits; any other window starts blank and leaves the list alone.
    function restoreSession() {
        if (ownsSession || !FirstBackend.instance.claimSession())
            return;

        // Files a crash recovered already have tabs; requestOpen finds those.
        var session = FirstBackend.instance.savedSession();
        for (var i = 0; i < session.files.length; ++i)
            requestOpen(session.files[i]);
        if (session.current.toString() !== "")
            activatePage(pageForUrl(session.current));

        ownsSession = true;
        saveSession();
    }

    function sessionToSave() {
        if (!closingWindow)
            return sessionFiles;

        var kept = closeOrder.filter(function(file) {
            return sessionFiles.indexOf(file) >= 0 || discardedOnClose.indexOf(file) >= 0;
        });
        return kept.concat(sessionFiles.filter(function(file) { return kept.indexOf(file) < 0; }));
    }

    function saveSession() {
        // No current page means the window is being torn down.
        if (!ownsSession || !currentPage)
            return;
        // Ask the page, not `backend`: this runs as currentPage changes, and
        // the window's `backend` may not have caught up with it yet.
        FirstBackend.instance.saveSession(sessionToSave(), closingWindow
            ? closeCurrent : currentPage.backend.fileUrl);
    }

    // Several open files can change at once (a git checkout, a sync). Ask about
    // them one at a time, each with its own tab in view.
    function reportExternalChange(page, deleted, locallyModified) {
        // Already asking about this very file; the answer will cover this change too.
        if (askingExternal && page === currentPage)
            return;

        var queued = externalChanges.filter(function(change) { return change.page !== page; });
        queued.push({ page: page, deleted: deleted, locallyModified: locallyModified });
        externalChanges = queued;
        showNextExternalChange();
    }

    function showNextExternalChange() {
        if (tabsLocked || externalChanges.length === 0)
            return;

        var change = externalChanges[0];
        externalChanges = externalChanges.slice(1);
        if (pages.indexOf(change.page) < 0) {
            showNextExternalChange();
            return;
        }
        activatePage(change.page);
        askingExternal = true;
        externalChangeDialog.deleted = change.deleted;
        externalChangeDialog.locallyModified = change.locallyModified;
        externalChangeDialog.open();
    }

    FontMetrics {
        id: writerFontMetrics
        font.family: backend.editorFont
        font.pixelSize: win.editorFontPixelSize
    }

    // Every hardcoded size in the interface is expressed at text scale 1.
    function scaledSize(pixels) {
        return Math.max(1, Math.round(pixels * win.textScale));
    }

    function toggleFullScreen() {
        win.visibility = win.visibility === Window.FullScreen
            ? Window.Windowed
            : Window.FullScreen;
    }

    // Only the search field and the next and previous controls select a
    // match. When the document changes underneath, the matches follow along
    // without taking the writer's caret.
    function updateSearch(selectMatch) {
        searchDelay.stop();
        var previous = searchMatchIndex >= 0 ? searchMatches[searchMatchIndex] : 0;
        searchMatches = backend.searchMatches(searchField.text);
        searchMatchIndex = selectMatch ? (searchMatches.length > 0 ? 0 : -1)
                                       : matchAtOrAfter(previous);
        showSearchMatch(selectMatch);
    }

    function matchAtOrAfter(position) {
        for (var i = 0; i < searchMatches.length; ++i) {
            if (searchMatches[i] >= position)
                return i;
        }
        return searchMatches.length > 0 ? 0 : -1;
    }

    function showSearchMatch(selectMatch) {
        var start = searchMatchIndex >= 0 ? searchMatches[searchMatchIndex] : -1;
        searchUpdating = true;
        backend.setSearchHighlight(searchField.text, start);
        if (selectMatch && start >= 0) {
            editor.select(start, start + searchField.text.length);
            editorFlick.ensureCursorVisible();
        }
        searchUpdating = false;
    }

    // Typing in the search field waits for a pause before searching, so
    // anything that acts on the matches catches up with the field first.
    function flushSearch() {
        if (searchDelay.running)
            updateSearch(true);
    }

    function moveSearch(direction) {
        // A pending search lands on its first match, which is where the
        // writer meant to go, rather than one past it.
        if (searchDelay.running) {
            updateSearch(true);
            return;
        }
        if (searchMatches.length === 0)
            return;
        searchMatchIndex = (searchMatchIndex + direction + searchMatches.length)
                           % searchMatches.length;
        showSearchMatch(true);
    }

    // The matches stop following the field and the text while the bar is
    // closed, and a search still waiting for a pause is dropped on closing,
    // so opening the bar searches again for what the field holds.
    function openSearch(withReplace) {
        searchOpen = true;
        if (withReplace)
            replaceOpen = true;
        searchField.forceActiveFocus();
        searchField.selectAll();
        // A search still waiting in an open bar lands on its first match.
        updateSearch(searchDelay.running);
    }

    function closeSearch() {
        searchDelay.stop();
        // Hand focus to the editor before hiding the bar. Hiding the field
        // that holds focus leaves the input method with nothing focused for
        // a moment, and fcitx5 can then miss the next Ctrl+F.
        Qt.inputMethod.reset();
        editor.forceActiveFocus();
        searchOpen = false;
        searchUpdating = true;
        backend.setSearchHighlight("", -1);
        editor.deselect();
        searchUpdating = false;
        replaceOpen = false;
    }

    // Restyling a large document for each letter typed makes typing a word
    // stall, so the search waits until the typing pauses.
    Timer {
        id: searchDelay
        interval: 150
        onTriggered: win.updateSearch(true)
    }

    Shortcut {
        sequence: "Ctrl+S"
        onActivated: backend.save()
    }

    Shortcut {
        sequence: "Ctrl+H"
        onActivated: win.openSearch(true)
    }

    Shortcut {
        sequence: "Ctrl+Shift+H"
        context: Qt.ApplicationShortcut
        onActivated: historyPopup.open()
    }

    Shortcut {
        sequence: "Ctrl+B"
        context: Qt.WindowShortcut
        onActivated: editor.wrapSelection("**")
    }

    Shortcut {
        sequence: "Ctrl+I"
        context: Qt.WindowShortcut
        onActivated: editor.wrapSelection("*")
    }

    Shortcut {
        sequence: "Ctrl+Shift+X"
        context: Qt.WindowShortcut
        onActivated: editor.wrapSelection("~~")
    }

    Shortcut {
        sequence: "Ctrl+K"
        context: Qt.WindowShortcut
        onActivated: editor.insertLink()
    }

    Shortcut {
        sequences: ["Ctrl+?", "Ctrl+/", "F1"]
        onActivated: shortcutsDialog.open()
    }

    Shortcut {
        // Ctrl++ is a different shortcut to Qt, not a shifted Ctrl+=, and it is
        // the only one a layout that puts + on its own key can reach.
        sequences: ["Ctrl+=", "Ctrl++"]
        onActivated: backend.increaseTextSize()
    }

    Shortcut {
        sequence: "Ctrl+-"
        onActivated: backend.decreaseTextSize()
    }

    Shortcut {
        sequence: "Ctrl+0"
        onActivated: backend.resetTextSize()
    }

    Shortcut {
        sequence: "Ctrl+O"
        onActivated: backend.openDialog()
    }

    Shortcut {
        sequence: "Ctrl+N"
        onActivated: backend.newWindow()
    }

    Shortcut {
        sequence: "Ctrl+T"
        context: Qt.ApplicationShortcut
        onActivated: win.newTab()
    }

    Shortcut {
        sequence: "Ctrl+W"
        context: Qt.ApplicationShortcut
        onActivated: win.closeTab(win.currentIndex)
    }

    Shortcut {
        sequences: ["Ctrl+Tab", "Ctrl+PgDown"]
        context: Qt.ApplicationShortcut
        onActivated: win.cycleTab(1)
    }

    Shortcut {
        sequences: ["Ctrl+Shift+Tab", "Ctrl+Shift+Backtab", "Ctrl+PgUp"]
        context: Qt.ApplicationShortcut
        onActivated: win.cycleTab(-1)
    }

    Instantiator {
        model: 9

        delegate: Shortcut {
            required property int index
            sequence: "Alt+" + (index + 1)
            context: Qt.ApplicationShortcut
            onActivated: win.activateTab(index)
        }
    }

    Shortcut {
        sequence: "Ctrl+Shift+S"
        onActivated: backend.saveAsDialog()
    }

    Shortcut {
        sequence: "Ctrl+P"
        onActivated: backend.printDocument()
    }

    Shortcut {
        sequence: "Ctrl+Shift+C"
        onActivated: backend.copyAsHtml()
    }

    Shortcut {
        sequences: ["Meta+F", "F11"]
        onActivated: toggleFullScreen()
    }

    Shortcut {
        sequence: "Ctrl+Z"
        context: Qt.WindowShortcut
        onActivated: editor.undo()
    }

    Shortcut {
        sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]
        context: Qt.WindowShortcut
        onActivated: editor.redo()
    }

    Shortcut {
        sequence: "Ctrl+F"
        onActivated: win.openSearch(false)
    }

    Shortcut {
        sequence: "Ctrl+G"
        enabled: win.searchOpen
        onActivated: win.moveSearch(1)
    }

    Connections {
        target: backend

        function onOpenDialogRequested() {
            openFileDialog.open();
        }

        function onSaveDialogRequested(suggestedUrl) {
            saveFileDialog.selectedFile = suggestedUrl;
            saveFileDialog.open();
        }

        function onSaveSucceeded() {
            // Only a save the writer chose in the prompt carries out the
            // pending close or open, never an auto-save that lands meanwhile.
            const confirmed = win.awaitingPendingSave;
            win.awaitingPendingSave = false;
            if (confirmed && win.pendingAction !== "")
                win.completePendingAction();
        }

        function onSaveFailed() {
            // A failed save leaves the document as it was, so the close or
            // open it was for is off; a later save must not carry it out.
            win.awaitingPendingSave = false;
            win.pendingAction = "";
        }
    }

    Dialogs.FileDialog {
        id: openFileDialog
        title: "Open File"
        fileMode: Dialogs.FileDialog.OpenFile
        nameFilters: ["Markdown files (*.md *.markdown)", "All files (*)"]
        onAccepted: win.requestOpen(selectedFile)
    }

    Dialogs.FileDialog {
        id: saveFileDialog
        title: "Save File"
        fileMode: Dialogs.FileDialog.SaveFile
        nameFilters: ["Markdown files (*.md *.markdown)", "All files (*)"]
        onAccepted: backend.saveAs(selectedFile)
        onRejected: {
            win.awaitingPendingSave = false;
            win.pendingAction = "";
        }
    }

    UnsavedChangesDialog {
        id: unsavedChangesDialog
        objectName: "unsavedChangesDialog"
        fileName: backend.fileName
        darkMode: win.darkMode
        textScale: win.textScale
        textColor: win.textColor
        strongTextColor: win.textColor
        activeButtonColor: backend.themeAccent
        containerWidth: win.width
        containerHeight: win.height

        // Discard must still mean discard, so nothing is auto-saved while
        // the writer decides.
        onAboutToShow: backend.holdAutoSave(true)

        onDiscardRequested: {
            win.askingUnsaved = false;
            backend.discardRecovery();
            win.completePendingAction(true);
        }

        onSaveRequested: {
            win.askingUnsaved = false;
            win.awaitingPendingSave = true;
            backend.save();
            // A named file saves on the spot and an unnamed one asks where to.
            // Still waiting with no save dialog up means the write failed, so
            // nothing closes and the tabs come free again.
            if (win.awaitingPendingSave && !saveFileDialog.visible) {
                win.awaitingPendingSave = false;
                win.pendingAction = "";
            }
        }
        onCancelRequested: {
            win.askingUnsaved = false;
            win.pendingAction = "";
        }
        onClosed: {
            backend.holdAutoSave(false);
            win.askingUnsaved = false;
            win.showNextExternalChange();
        }
    }

    ExternalChangeDialog {
        id: externalChangeDialog
        objectName: "externalChangeDialog"
        darkMode: win.darkMode
        textScale: win.textScale
        textColor: win.textColor
        strongTextColor: win.textColor
        activeButtonColor: backend.themeAccent
        containerWidth: win.width
        containerHeight: win.height

        onKeepRequested: backend.keepExternalVersion()
        onReloadRequested: backend.reloadFromDisk()
        onClosed: {
            win.askingExternal = false;
            win.showNextExternalChange();
        }
    }

    ShortcutsDialog {
        id: shortcutsDialog
        darkMode: win.darkMode
        textScale: win.textScale
        textColor: win.textColor
        activeButtonColor: backend.themeAccent
        containerWidth: win.width
        containerHeight: win.height
    }

    header: TabStrip {
        id: tabStrip
        objectName: "tabStrip"
        pages: win.pages
        currentPage: win.currentPage
        pageColor: win.pageColor
        textColor: win.textColor
        accentColor: backend.themeAccent
        textScale: win.textScale
        onActivateRequested: function(index) { win.activateTab(index) }
        onCloseRequested: function(index) { win.closeTab(index) }
        onNewTabRequested: win.newTab()
    }

    Item {
        anchors.fill: parent

        // One page per tab: a document, Flickable and TextEdit of its own, so
        // each tab keeps its undo history, caret and scroll position. Inside a
        // page `backend` is that page's document.
        Item {
            id: pageHost
            anchors.fill: parent
        }

        Component {
            id: pageComponent

            Item {
                id: page

                property var backend
                readonly property Item editorItem: editor
                readonly property Item flickItem: editorFlick
                // A blank, untouched page has nothing to lose, so Open reuses it.
                readonly property bool pristine: !backend.modified
                    && backend.fileUrl.toString() === "" && editor.length === 0
                // What an unnamed tab is called: its first line of writing.
                property string headline: ""

                anchors.fill: parent
                visible: win.currentPage === page

                Connections {
                    target: page.backend

                    function onExternalChangeDetected(deleted, locallyModified) {
                        win.reportExternalChange(page, deleted, locallyModified);
                    }
                }

                Connections {
                    target: editor

                    function onTextChanged() {
                        if (page.backend.fileUrl.toString() !== "")
                            return;
                        var firstLine = editor.getText(0, 200).replace(/^\s+/, "").split("\n")[0];
                        page.headline = firstLine.replace(/^#+\s*/, "").trim().slice(0, 40);
                    }
                }

                Flickable {
                    id: editorFlick
            objectName: "editorScroll"
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
            // Inset the scrolling area by the footer strip at both ends, so
            // scrolled text never runs under the footer buttons, status, or
            // word count, and stops just as far short of the top edge.
            anchors.topMargin: win.footerHeight
            anchors.bottomMargin: win.footerHeight
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(height, editor.y + editor.implicitHeight + 220)
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        // Wheel scrolling moves contentY directly rather than
                        // flicking the Flickable, so the bar has to be told about
                        // that activity; linger briefly after the last event.
                        active: hovered || pressed || wheelScroll.running || scrollLinger.running
                    }

            // Also lingers after paging through the document from the
            // keyboard, so the bar shows where the jump landed. Writing past
            // the bottom edge scrolls too, but leaves the bar hidden.
                    Timer {
                        id: scrollLinger
                objectName: "scrollLinger"
                        interval: 600
                    }

                    // Flickable turns a wheel notch into a flick sized by the small
                    // application font, which crawls next to a browser. Reproduce
                    // Chromium's wheel physics instead (cc::ScrollOffsetAnimationCurve):
                    // each notch moves 3 lines of 40px towards a running target, the
                    // animation gets shorter as the outstanding distance grows, and a
                    // notch landing mid-animation carries the current velocity into
                    // the new curve, so sustained spinning keeps picking up speed.
                    readonly property real wheelStep: win.scaledSize(120)

                    FrameAnimation {
                        id: wheelScroll
                        running: false

                        property real startY: 0
                        property real targetY: 0
                        property real duration: 0.2
                        // Cubic bezier easing; ease-in-out (0.42, 0, 0.58, 1) for a
                        // fresh scroll, with y1 tilted on retarget so the curve's
                        // initial slope matches the velocity it inherits.
                        property real cx1: 0.42
                        property real cy1: 0
                        readonly property real cx2: 0.58
                        readonly property real cy2: 1

                        onTriggered: {
                            var x = elapsedTime / duration;
                            if (x >= 1) {
                                editorFlick.contentY = editorFlick.snapToPixel(targetY);
                                stop();
                                return;
                            }
                            editorFlick.contentY = editorFlick.snapToPixel(
                                startY + (targetY - startY) * curveY(solveCurve(x)));
                        }

                        function begin(from, to, dur, slope) {
                            startY = from;
                            targetY = to;
                            duration = dur;
                            cx1 = 0.42;
                            cy1 = 0.42 * Math.max(-1000, Math.min(1000, slope));
                            restart();
                        }

                        function retarget(newTarget) {
                            var s = solveCurve(Math.min(1, elapsedTime / duration));
                            var pos = startY + (targetY - startY) * curveY(s);
                            var delta = newTarget - pos;
                            if (Math.abs(delta) < 0.5) {
                                editorFlick.contentY = newTarget;
                                stop();
                                return;
                            }

                            var velocity = curveDY(s) / Math.max(1e-6, curveDX(s))
                                * (targetY - startY) / duration;
                            var dur = editorFlick.wheelDuration(delta);
                            // When already moving faster than the eased curve would,
                            // bound the duration by the time to target at the current
                            // velocity; the 2.5x covers the ease-out tail.
                            if (velocity !== 0 && delta / velocity > 0)
                                dur = Math.min(dur, delta / velocity * 2.5);
                            begin(pos, newTarget, dur, velocity * dur / delta);
                        }

                        // Cubic bezier through (0,0), (cx1,cy1), (cx2,cy2), (1,1),
                        // evaluated by Newton-solving the curve parameter from x.
                        function curveX(s) { return 3 * s * (1 - s) * ((1 - s) * cx1 + s * cx2) + s * s * s; }
                        function curveY(s) { return 3 * s * (1 - s) * ((1 - s) * cy1 + s * cy2) + s * s * s; }
                        function curveDX(s) { return 3 * (1 - s) * (1 - s) * cx1 + 6 * (1 - s) * s * (cx2 - cx1) + 3 * s * s * (1 - cx2); }
                        function curveDY(s) { return 3 * (1 - s) * (1 - s) * cy1 + 6 * (1 - s) * s * (cy2 - cy1) + 3 * s * s * (1 - cy2); }

                        function solveCurve(x) {
                            var s = x;
                            for (var i = 0; i < 8; ++i) {
                                var error = curveX(s) - x;
                                if (Math.abs(error) < 0.001)
                                    break;
                                var d = curveDX(s);
                                if (Math.abs(d) < 1e-6)
                                    break;
                                s = Math.max(0, Math.min(1, s - error / d));
                            }
                            return s;
                        }
                    }

                    WheelHandler {
                        // Wayland compositors route every pointer's scroll through
                        // one seat device that Qt classifies as a touchpad, so the
                        // device type cannot tell a mouse wheel from two-finger
                        // scrolling. Distinguish by event shape instead: discrete
                        // wheel notches arrive with only angleDelta set, while
                        // finger scrolling carries pixel-precise pixelDelta.
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(wheel) {
                    if (wheel.modifiers & Qt.ControlModifier) {
                        editorFlick.zoomByWheel(wheel);
                        wheel.accepted = true;
                        return;
                    }

                            scrollLinger.restart();
                            if (wheel.pixelDelta.y !== 0)
                                editorFlick.scrollTo(editorFlick.clampContentY(editorFlick.contentY - wheel.pixelDelta.y));
                            else
                                editorFlick.scrollByWheel(wheel);
                            wheel.accepted = true;
                        }
                    }

                    onMovementStarted: wheelScroll.stop()
            onContentYChanged: editor.hoveredLinkUrl = ""

            // Ctrl+wheel changes the text size, as it does in a browser. A
            // wheel notch is a whole step, but a touchpad trickles in pixels,
            // so bank the fractions and step once a whole one is scrolled.
            property real zoomNotches: 0

            function zoomByWheel(wheel) {
                // Finger scrolling synthesizes an angleDelta too, so pixelDelta
                // is the one to test first, as in onWheel.
                var notches = wheel.pixelDelta.y !== 0
                    ? wheel.pixelDelta.y / 50
                    : wheel.angleDelta.y / 120;
                if (zoomNotches * notches < 0)
                    zoomNotches = 0;

                zoomNotches += notches;
                while (zoomNotches >= 1) {
                    backend.increaseTextSize();
                    zoomNotches -= 1;
                }
                while (zoomNotches <= -1) {
                    backend.decreaseTextSize();
                    zoomNotches += 1;
                }
            }

                    function scrollByWheel(wheel) {
                        // High-resolution wheels report fractional notches; feed
                        // those through the same animated path, like Chromium does
                        // for every wheel-source event.
                        var notches = wheel.angleDelta.y / 120;
                        if (notches === 0)
                            return;

                        if (wheelScroll.running) {
                            wheelScroll.retarget(clampContentY(wheelScroll.targetY - notches * wheelStep));
                            return;
                        }

                        var target = clampContentY(contentY - notches * wheelStep);
                        if (target !== contentY)
                            wheelScroll.begin(contentY, target, wheelDuration(target - contentY), 0);
                    }

                    // Chromium's inverse-delta duration: 200ms for a single notch,
                    // ramping down to 100ms once 480px are outstanding.
                    function wheelDuration(delta) {
                        var pixels = Math.abs(delta) / win.textScale;
                        return Math.max(6, Math.min(12, 14 - pixels / 60)) / 60;
                    }

                    function clampContentY(y) {
                        return Math.max(0, Math.min(Math.max(0, contentHeight - height), y));
                    }

                    // Whole device pixels keep natively hinted glyphs from
                    // re-rasterizing mid-animation, which reads as shimmer.
                    function snapToPixel(y) {
                        return Math.round(y * Screen.devicePixelRatio) / Screen.devicePixelRatio;
                    }

                    // Jump to a position, abandoning any wheel animation still running.
                    function scrollTo(y) {
                        wheelScroll.stop();
                        contentY = snapToPixel(y);
                    }

                    // Keep the editing caret within the viewport so writing past the
                    // bottom edge scrolls the page along with the text.
                    function ensureCursorVisible() {
                        var margin = win.editorFontPixelSize * 2;
                        var cursorTop = editor.y + editor.cursorRectangle.y;
                        var cursorBottom = cursorTop + editor.cursorRectangle.height;
                        var maxContentY = Math.max(0, contentHeight - height);

                        if (cursorBottom + margin > contentY + height)
                            scrollTo(Math.min(maxContentY, cursorBottom + margin - height));
                        else if (cursorTop - margin < contentY)
                            scrollTo(Math.max(0, cursorTop - margin));
                    }

                    TextEdit {
                        id: editor
                        objectName: "sourceEditor"
                        x: Math.round((editorFlick.width - width) / 2)
                // The resting position counts from the window's top edge, so
                // take back the top inset the Flickable already adds.
                y: Math.max(0, Math.max(42, Math.round(win.height * 0.05)) - win.footerHeight)
                        width: win.editorWidth
                        height: Math.max(editorFlick.height - y - 96, implicitHeight + 20)
                        text: ""
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        persistentSelection: true
                        activeFocusOnPress: true
                        color: win.textColor
                selectedTextColor: win.selectionTextColor
                        selectionColor: win.selectionFill
                font.family: backend.editorFont
                        font.pixelSize: win.editorFontPixelSize
                        font.weight: Font.Normal
                        // Native rendering hints glyphs to the pixel grid, which is
                        // crispest at whole scale factors but misplaces and unevenly
                        // rasterizes glyphs at fractional ones (and goes stale when
                        // the compositor delivers the fractional scale after the
                        // first frame). Fall back to Qt's scalable renderer there.
                        renderType: Screen.devicePixelRatio % 1 === 0 ? TextEdit.NativeRendering : TextEdit.QtRendering
                        cursorDelegate: Rectangle {
                            width: 1
                    color: win.textColor
                        }
                        onCursorRectangleChanged: editorFlick.ensureCursorVisible()
                onCursorPositionChanged: backend.setCaretPosition(cursorPosition)
                onFontChanged: backend.documentFontChanged()

                // One edit command, so a single undo takes the change back.
                function replaceText(start, end, replacement) {
                    backend.replaceRange(start, end, replacement);
                        }

                function replaceSelectionWith(replacement) {
                    EditorMutations.replaceRange(editor, selectionStart, selectionEnd, replacement);
                }

                function wrapSelection(marker) {
                            forceActiveFocus();
                    EditorMutations.toggleWrap(editor, marker,
                                               backend.emphasisSpanAt(cursorPosition, marker));
                        }

                        function insertLink() {
                    forceActiveFocus();
                    var start = selectionStart;
                    var end = selectionEnd;
                            var selected = text.slice(start, end);
                            var url = backend.clipboardUrl();
                            var label = selected.length > 0 ? selected : "link text";
                    var markdown = markdownLink(label, url.length > 0 ? url : "https://");
                    var labelLength = escapeMarkdownLinkText(label).length;
                            if (selected.length === 0) {
                                EditorMutations.replaceRange(editor, start, end, markdown,
                                                     1, 1 + labelLength);
                            } else if (url.length === 0) {
                                EditorMutations.replaceRange(editor, start, end, markdown,
                                                     labelLength + 3,
                                                             markdown.length - 1);
                            } else {
                                EditorMutations.replaceRange(editor, start, end, markdown);
                            }
                        }

                        function smartReturn(softBreak) {
                            if (softBreak) {
                                replaceSelectionWith("\n");
                                return;
                            }
                            var lineStart = text.lastIndexOf("\n", cursorPosition - 1) + 1;
                            var line = text.slice(lineStart, cursorPosition);
                    if (backend.insideFence(cursorPosition)) {
                                replaceSelectionWith("\n");
                                return;
                            }
                            var match = line.match(/^(\s*)([-+*]|\d+[.)]|>+)\s+(.*)$/);
                            if (match) {
                                if (match[3].length === 0) {
                                    EditorMutations.replaceRange(editor, lineStart,
                                                                 cursorPosition, "\n");
                                } else {
                                    var marker = match[2];
                                    if (/^\d/.test(marker))
                                        marker = (parseInt(marker) + 1) + marker.slice(-1);
                                    replaceSelectionWith("\n" + match[1] + marker + " ");
                                }
                                return;
                            }
                    // A new paragraph stands apart from the one above it by a
                    // blank line, which is the second break here. A line that
                    // is already blank has nothing to stand apart from, so
                    // that break would only be a gap nobody asked for.
                    // The break lands on what the selection leaves behind, which
                    // is not the caret's line when it was dragged right to left.
                    var start = selectionStart;
                    var end = selectionEnd;
                    var head = text.slice(text.lastIndexOf("\n", start - 1) + 1, start);
                    var lineEnd = text.indexOf("\n", end);
                    var rest = lineEnd < 0 ? text.slice(end)
                                           : text.slice(end, lineEnd);
                    if (/^\s*$/.test(head) && /^\s*$/.test(rest)) {
                        replaceSelectionWith("\n");
                        return;
                    }
                            replaceSelectionWith("\n\n");
                        }

                // Tab nests the list items the caret or selection touches four
                // spaces deeper, and Shift+Tab lifts them back out by the same
                // step. Lines that are neither items, their indented
                // continuations, nor blank, and code fences, leave Tab alone.
                function indentListItems(outdent) {
                    // "* * *" and "- - -" are rules, not items.
                    var listItem = function(line) {
                        return /^[ \t]*(?:[-+*]|\d+[.)])[ \t]/.test(line)
                            && !/^ {0,3}([-*])([ \t]*\1){2,}[ \t]*$/.test(line);
                    };
                    // A tab runs to the next four-column stop.
                    var columns = function(line) {
                        return line.match(/^[ \t]*/)[0].split("").reduce(function(column, c) {
                            return c === "\t" ? column + 4 - column % 4 : column + 1;
                        }, 0);
                    };

                    // A selection that ends at the start of a line leaves it be.
                    // lastIndexOf would read -1 as 0, a newline right there.
                    var start = selectionStart > 0 ? text.lastIndexOf("\n", selectionStart - 1) + 1 : 0;
                    var end = text.indexOf("\n", Math.max(start, selectionEnd - 1));
                    if (end < 0)
                        end = text.length;
                    var lines = text.slice(start, end).split("\n");
                    // The selection starts at an item and holds only lines that
                    // belong to one: other items, blanks, and indented lines.
                    // A fence indented under an item moves along with it whole;
                    // a selection that starts or ends inside code would split it.
                    var filled = lines.filter(function(line) { return /\S/.test(line); });
                    if (!listItem(filled[0] || "")
                        || filled.some(function(line) { return /^\S/.test(line) && !listItem(line); })
                        || backend.insideFence(start)
                        || backend.insideFence(end))
                        return false;

                    // Every line moves by the same step, so the nesting within
                    // the selection is kept. Four spaces nest under any marker
                    // up to "99.", and Shift+Tab lifts no further than the
                    // shallowest line can go.
                    var step = outdent ? -Math.min.apply(null, [4].concat(filled.map(columns))) : 4;
                    if (step === 0)
                        return true;
                    var moved = lines.map(function(line) {
                        var lead = line.match(/^[ \t]*/)[0];
                        return /\S/.test(line)
                            ? " ".repeat(columns(line) + step) + line.slice(lead.length)
                            : line;
                    });
                    var nested = moved.join("\n");
                    var from = Math.max(start, selectionStart + moved[0].length - lines[0].length);
                    // Neither end of the selection leaves its line, even when
                    // the indent it sat in is gone.
                    var lastStart = start + nested.length - moved[moved.length - 1].length;
                    var to = Math.max(from, lastStart, selectionEnd + nested.length - (end - start));
                    var forward = cursorPosition === selectionEnd;
                    replaceText(start, end, nested);
                    select(forward ? from : to, forward ? to : from);
                    return true;
                }

                        function escapeMarkdownLinkText(linkText) {
                            return linkText.replace(/\\/g, "\\\\")
                                           .replace(/\[/g, "\\[")
                                           .replace(/\]/g, "\\]");
                        }

                        function escapeMarkdownLinkDestination(linkUrl) {
                            return linkUrl.replace(/\\/g, "\\\\")
                                          .replace(/\(/g, "\\(")
                                          .replace(/\)/g, "\\)");
                        }

                function markdownLink(label, url) {
                    return "[" + escapeMarkdownLinkText(label) + "]("
                        + escapeMarkdownLinkDestination(url) + ")";
                }

                        function pasteClipboardUrlAsMarkdownLink() {
                    var start = selectionStart;
                    var end = selectionEnd;
                            if (start === end)
                                return false;

                            var url = backend.clipboardUrl();
                            if (url === "")
                                return false;

                            var selected = text.slice(start, end);
                            var leading = selected.match(/^\s*/)[0];
                            var trailing = selected.match(/\s*$/)[0];
                            var linkText = selected.slice(leading.length,
                                                          selected.length - trailing.length);
                            if (linkText === "")
                                return false;

                    replaceSelectionWith(leading + markdownLink(linkText, url) + trailing);
                            return true;
                        }

                        function pasteClipboardAsPlainText() {
                            var pastedText = backend.clipboardText();
                            if (pastedText.length > 0)
                                replaceSelectionWith(pastedText);
                        }

                        function moveCursorVisibly(direction) {
                            if (selectionStart !== selectionEnd) {
                        cursorPosition = direction > 0 ? selectionEnd : selectionStart;
                                return;
                            }

                    var pos = backend.cursorPositionStep(cursorPosition, direction);
                    cursorPosition = Math.max(0, Math.min(length, pos));
                        }

                        function movePage(direction, extendSelection) {
                            var pageStep = Math.max(win.editorFontPixelSize,
                                                    editorFlick.height - win.editorFontPixelSize * 2);
                            var rect = cursorRectangle;
                            var targetY = rect.y + rect.height / 2 + direction * pageStep;
                            var target = positionAt(rect.x, Math.max(0, targetY));
                            if (extendSelection)
                                moveCursorSelection(target, TextEdit.SelectCharacters);
                            else
                                cursorPosition = target;
                        }

                        function deleteParagraphBreakBehindCursor() {
                            if (selectionStart !== selectionEnd || cursorPosition < 2)
                                return false;

                    // getText reads just the two characters, where text would
                    // copy the whole document on every Backspace.
                    if (getText(cursorPosition - 2, cursorPosition) !== "\n\n")
                                return false;

                            var start = cursorPosition - 2;
                    var lineEnd = text.indexOf("\n", cursorPosition);
                    var line = lineEnd < 0 ? text.slice(cursorPosition)
                                           : text.slice(cursorPosition, lineEnd);
                    // Something on the caret's line and the pair above it is a
                    // paragraph break and nothing else, either the one Return
                    // wrote to end a paragraph or the one the writer is now
                    // closing to join what it separates. Both breaks go.
                    if (/^\s*$/.test(line)) {
                        // On a blank line Return writes a single break, so up
                        // here the pair may be that break and one that was
                        // already in the document. Above a blank line Return
                        // writes a single break too, and so wrote neither of
                        // these.
                        var above = text.slice(text.lastIndexOf("\n", start - 1) + 1, start);
                        if (/^\s*$/.test(above))
                            return false;
                        // Past that the two Returns leave the same text and the
                        // same caret, and no reading of either says which was
                        // pressed. What decides instead is that the gap is left
                        // standing: both breaks go only while a blank line of
                        // it survives them. The end of the document below the
                        // caret leaves it none...
                        if (lineEnd < 0)
                            return false;
                        // ...and so does the next paragraph, which the pair
                        // would otherwise be pulled up against.
                        var belowEnd = text.indexOf("\n", lineEnd + 1);
                        var below = belowEnd < 0 ? text.slice(lineEnd + 1)
                                                 : text.slice(lineEnd + 1, belowEnd);
                        if (!/^\s*$/.test(below))
                            return false;
                    }

                            remove(start, cursorPosition);
                            cursorPosition = start;
                            return true;
                        }

                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: function(event) {
                            var pasteKey = (event.key === Qt.Key_V)
                                && (event.modifiers & Qt.ControlModifier)
                                && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier));
                            var shiftInsert = (event.key === Qt.Key_Insert)
                                && (event.modifiers & Qt.ShiftModifier)
                                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
                            if (pasteKey || shiftInsert) {
                                if (!pasteClipboardUrlAsMarkdownLink())
                                    pasteClipboardAsPlainText();
                                event.accepted = true;
                                return;
                            }

                    var pageKey = event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp;
                    var documentEdgeKey = (event.key === Qt.Key_Home || event.key === Qt.Key_End)
                        && (event.modifiers & Qt.ControlModifier);
                    if (pageKey || documentEdgeKey)
                        scrollLinger.restart();

                            var returnKey = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
                            var commandModifier = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
                            if (returnKey && !commandModifier) {
                                smartReturn(event.modifiers & Qt.ShiftModifier);
                                event.accepted = true;
                            } else if (!commandModifier && event.key === Qt.Key_Backspace
                                       && deleteParagraphBreakBehindCursor()) {
                                event.accepted = true;
                            } else if (!commandModifier && !(event.modifiers & Qt.ShiftModifier)
                                       && event.key === Qt.Key_Right) {
                                moveCursorVisibly(1);
                                event.accepted = true;
                            } else if (!commandModifier && !(event.modifiers & Qt.ShiftModifier)
                                       && event.key === Qt.Key_Left) {
                                moveCursorVisibly(-1);
                                event.accepted = true;
                            } else if (!commandModifier
                               && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                               && indentListItems(event.key === Qt.Key_Backtab
                                                  || (event.modifiers & Qt.ShiftModifier))) {
                        event.accepted = true;
                    } else if (!commandModifier
                                       && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
                                movePage(event.key === Qt.Key_PageDown ? 1 : -1,
                                         event.modifiers & Qt.ShiftModifier);
                                event.accepted = true;
                            }
                        }

                        onTextChanged: {
                    hoveredLinkUrl = "";
                            if (win.searchUpdating)
                                return;
                            var contentChanged = backend.editorTextChanged();
                            if (win.searchOpen && contentChanged)
                        win.updateSearch(false);
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: "# Start writing"
                    visible: editor.length === 0 && !editor.activeFocus
                            color: win.mutedColor
                            font.family: editor.font.family
                            font.pixelSize: editor.font.pixelSize
                            font.weight: editor.font.weight
                        }

                property string hoveredLinkUrl: ""
                property real linkHoverX: 0
                property real linkHoverY: 0

                // positionAt() snaps to the nearest caret, even past the end of a
                // line, so only count a character the pointer is inside: the one
                // on either side of that caret, whichever way the text runs.
                function linkUrlUnder(x, y) {
                    var caret = positionAt(x, y);
                    for (var position = Math.max(0, caret - 1);
                         position <= caret && position < length; ++position) {
                        var box = positionToRectangle(position);
                        var next = positionToRectangle(position + 1);
                        // A hidden marker has no width; only a line's last
                        // character needs an estimate.
                        var edge = next.y === box.y
                            ? next.x : box.x + writerFontMetrics.averageCharacterWidth;
                        if (y >= box.y && y < box.y + box.height
                                && x >= Math.min(box.x, edge) && x < Math.max(box.x, edge))
                            return backend.linkUrlAt(position);
                    }
                    return "";
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    cursorShape: Qt.IBeamCursor
                    onPositionChanged: (mouse) => {
                        editor.linkHoverX = mouse.x;
                        editor.linkHoverY = mouse.y;
                        editor.hoveredLinkUrl = editor.linkUrlUnder(mouse.x, mouse.y);
                    }
                    onExited: editor.hoveredLinkUrl = ""
                }

                ToolTip {
                    visible: editor.hoveredLinkUrl.length > 0
                    x: editor.linkHoverX + 12
                    y: editor.linkHoverY + 20
                    contentItem: Label {
                        objectName: "linkTooltipText"
                        // A destination is document text; AutoText would render
                        // one that looks like HTML instead of showing it.
                        textFormat: Text.PlainText
                        text: editor.hoveredLinkUrl
                        font.family: backend.editorFont
                        font.pixelSize: win.scaledSize(12)
                        elide: Text.ElideMiddle
                    }
                    width: Math.min(implicitWidth, win.width - 32)
                }

                        Component.onCompleted: {
                            backend.attachDocument(textDocument);
                            forceActiveFocus();
                        }
                    }
                }
            }
        }

        Row {
            id: footerStatus
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.bottomMargin: 10
            spacing: 12
            opacity: 0.55

            FooterIconButton {
                objectName: "saveButton"
                iconName: "save"
                iconColor: win.mutedColor
                tooltip: "Save"
                onClicked: backend.save()
            }

            FooterIconButton {
                objectName: "openButton"
                iconName: "open"
                iconColor: win.mutedColor
                tooltip: "Open"
                onClicked: backend.openDialog()
            }

            FooterIconButton {
                id: historyButton
                objectName: "historyButton"
                iconName: "history"
                iconColor: win.mutedColor
                tooltip: "Checkpoints"
                onClicked: historyPopup.open()
            }

            FooterIconButton {
                id: fontButton
                objectName: "fontButton"
                iconName: "font"
                iconColor: win.mutedColor
                tooltip: "Font"
                onClicked: fontPicker.opened ? fontPicker.close() : fontPicker.open()
            }

            Label {
                text: backend.status
                color: win.mutedColor
                font.family: "IBM Plex Mono"
                font.pixelSize: win.scaledSize(11)
                visible: text !== ""
                elide: Text.ElideRight
                width: Math.min(360, win.width / 3)
                height: win.scaledSize(16)
                verticalAlignment: Text.AlignVCenter
            }
        }

        FontPicker {
            id: fontPicker
            objectName: "fontPicker"
            // Parented to its button, so a press on the button is not a press
            // outside that closes it only for the click to open it again.
            parent: fontButton
            x: -8
            y: -height - 10
            width: win.scaledSize(320)
            maximumHeight: Math.min(win.scaledSize(440), win.height - 80)
            fonts: backend.availableFonts
            currentFont: backend.editorFont
            defaultFont: "IBM Plex Mono"
            darkMode: win.darkMode
            textScale: win.textScale
            textColor: win.textColor
            mutedColor: win.mutedColor
            highlightColor: backend.themeAccent
            onFontChosen: function(family) { backend.editorFont = family; }
            onClosed: editor.forceActiveFocus()
        }

        Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 12
            anchors.bottomMargin: 10
            text: backend.wordCount + (backend.wordCount === 1 ? " Word" : " Words")
            color: win.mutedColor
            opacity: 0.75
            font.family: "IBM Plex Mono"
            font.pixelSize: win.scaledSize(11)
        }

        HistoryPopup {
            id: historyPopup
            objectName: "historyPopup"
            parent: Overlay.overlay
            anchorItem: historyButton
            darkMode: win.darkMode
            textScale: win.textScale
            textColor: win.textColor
            strongTextColor: win.textColor
            mutedColor: win.mutedColor
            checkpoints: backend.checkpoints
            onRestoreRequested: function(id) { backend.restoreCheckpoint(id) }
        }


        Pane {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 12
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: win.scaledSize(win.replaceOpen ? 104 : 56)
            visible: win.searchOpen
            z: 10
            leftPadding: 16
            rightPadding: 8
            topPadding: 0
            bottomPadding: 0
            Material.elevation: 8
            // Reaches here from either field or the buttons beside them.
            Keys.onEscapePressed: function(event) {
                win.closeSearch();
                event.accepted = true;
            }

            background: Rectangle {
                radius: 9
                color: win.darkMode ? "#22221f" : "#fffef2"
            }

            RowLayout {
                anchors.fill: parent
                spacing: 8

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextInput {
                        id: searchField
                        objectName: "searchField"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: win.replaceOpen ? parent.height / 2 : parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        activeFocusOnTab: true
                        color: win.textColor
                        selectionColor: win.selectionFill
                        selectedTextColor: win.selectionTextColor
                        font.pixelSize: win.scaledSize(17)
                        clip: true
                        onTextChanged: searchDelay.restart()
                        Keys.onReturnPressed: function(event) {
                            win.moveSearch((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                            event.accepted = true;
                        }
                    }

                    TextInput {
                        id: replaceField
                        objectName: "replaceField"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height / 2
                        visible: win.replaceOpen
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        activeFocusOnTab: true
                        clip: true
                        color: win.textColor
                        selectionColor: win.selectionFill
                        selectedTextColor: win.selectionTextColor
                        font.pixelSize: win.scaledSize(17)
                        Keys.onReturnPressed: replaceCurrentButton.clicked()
                    }

                    Label {
                        anchors.verticalCenter: replaceField.verticalCenter
                        text: "Replace with"
                        visible: win.replaceOpen && replaceField.text.length === 0
                        color: win.mutedColor
                        font.pixelSize: win.scaledSize(17)
                    }

                    Label {
                        anchors.verticalCenter: searchField.verticalCenter
                        text: "Find"
                        visible: searchField.text.length === 0
                        color: win.mutedColor
                        font.pixelSize: win.scaledSize(17)
                    }
                }

                Label {
                    Layout.preferredWidth: win.scaledSize(58)
                    Layout.fillHeight: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: win.searchMatches.length === 0
                        ? "0/0"
                        : (win.searchMatchIndex + 1) + "/" + win.searchMatches.length
                    color: win.darkMode ? win.textColor : "#62635f"
                    font.pixelSize: win.scaledSize(16)
                }

                Button {
                    id: replaceCurrentButton
                    objectName: "replaceButton"
                    visible: win.replaceOpen
                    text: "Replace"
                    onClicked: {
                        win.flushSearch();
                        if (win.searchMatchIndex < 0) return;
                        var start = win.searchMatches[win.searchMatchIndex];
                        var replacement = replaceField.text;
                        EditorMutations.replaceRange(editor, start,
                                                     start + searchField.text.length,
                                                     replacement);
                        // Carry on past what was just written, so a replacement
                        // the query also matches is not found again.
                        win.searchMatches = backend.searchMatches(searchField.text);
                        win.searchMatchIndex = win.matchAtOrAfter(start + replacement.length);
                        win.showSearchMatch(true);
                    }
                }

                Button {
                    objectName: "replaceAllButton"
                    visible: win.replaceOpen
                    text: "All"
                    onClicked: {
                        win.flushSearch();
                        var query = searchField.text;
                        var matches = win.searchMatches;
                        if (query.length === 0 || matches.length === 0) return;
                        // One replacement over the span of every match, so a
                        // single undo takes them all back.
                        var first = matches[0];
                        var replaced = "";
                        var position = first;
                        for (var i = 0; i < matches.length; ++i) {
                            replaced += editor.text.slice(position, matches[i]) + replaceField.text;
                            position = matches[i] + query.length;
                        }
                        EditorMutations.replaceRange(editor, first, position, replaced);
                        win.updateSearch(false);
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 34
                    color: win.darkMode ? "#6f6f62" : "#d5d56e"
                }

                SearchIconButton {
                    iconName: "up"
                    iconColor: win.darkMode ? win.textColor : "#62635f"
                    onClicked: win.moveSearch(-1)
                }

                SearchIconButton {
                    iconName: "down"
                    iconColor: win.darkMode ? win.textColor : "#62635f"
                    onClicked: win.moveSearch(1)
                }

                SearchIconButton {
                    iconName: "close"
                    iconColor: win.darkMode ? win.textColor : "#62635f"
                    onClicked: win.closeSearch()
                }
            }
        }
    }

    Component.onCompleted: {
        addPage(FirstBackend.instance);
        // A window that died with several unsaved tabs left a snapshot for
        // each. The first tab has claimed one; give the rest a tab apiece.
        for (var i = 0; i < 100 && backend.hasOrphanedRecovery(); ++i)
            newTab();
        activateTab(0);

        var geometry = backend.windowGeometry();
        if (geometry.x >= 0) x = geometry.x;
        if (geometry.y >= 0) y = geometry.y;
        width = geometry.width;
        height = geometry.height;
        if (geometry.maximized) showMaximized();
    }

    Component.onDestruction: backend.saveWindowGeometry(x, y, width, height, visibility === Window.Maximized)

}
