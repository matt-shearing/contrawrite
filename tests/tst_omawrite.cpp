#include <QtTest>
#include <QFile>
#include <QFont>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickStyle>
#include <QStandardPaths>
#include <QWindow>

#include "backend.h"
#include "markdownhighlighter.h"

class OmawriteTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        QVERIFY(m_settingsDirectory.isValid());
        QStandardPaths::setTestModeEnabled(true);
        QQuickStyle::setStyle(QStringLiteral("Material"));
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                           m_settingsDirectory.path());
    }

    void init() {
        // A window gives every crash snapshot it finds a tab, so one test's
        // leftovers must not turn up as extra tabs in the next.
        QDir state(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
        const auto leftovers = state.entryList({QStringLiteral("recovery-*"),
                                                QStringLiteral("contrawrite-session*")},
                                               QDir::Files);
        for (const QString &leftover : leftovers)
            state.remove(leftover);
    }

    void countsWords() {
        QCOMPARE(Backend::countWords(QStringLiteral("one two-three don't 42")), 4);
        QCOMPARE(Backend::countWords(QStringLiteral("你好 世界")), 2);
        QCOMPARE(Backend::countWords(QString()), 0);
    }

    void normalizesLinks() {
        QCOMPARE(Backend::normalizedLinkUrl(QStringLiteral("www.example.com/path")),
                 QStringLiteral("https://www.example.com/path"));
        QCOMPARE(Backend::normalizedLinkUrl(QStringLiteral("mailto:writer@example.com")),
                 QStringLiteral("mailto:writer@example.com"));
        QVERIFY(Backend::normalizedLinkUrl(QStringLiteral("example.com")).isEmpty());
        QVERIFY(Backend::normalizedLinkUrl(QStringLiteral("file:///tmp/private")).isEmpty());
    }

    void suggestsSafeNames() {
        QCOMPARE(Backend::suggestedFileName(QStringLiteral("My first draft\nBody")),
                 QStringLiteral("My first draft.md"));
        QCOMPARE(Backend::suggestedFileName(QStringLiteral("A/B")), QStringLiteral("A-B.md"));
        QCOMPARE(Backend::suggestedFileName(QString()), QStringLiteral("Untitled.md"));
        QCOMPARE(Backend::suggestedFileName(QStringLiteral("Already.md")),
                 QStringLiteral("Already.md"));
    }

    void findsInlineMarkdownRanges() {
        const auto markup = MarkdownHighlighter::inlineMarkup(
            QStringLiteral("**bold** and *italic* and [site](https://example.com)"));
        QCOMPARE(markup.size(), 3);
        QCOMPARE(markup.at(0).content.start, 2);
        QCOMPARE(markup.at(0).content.length, 4);
        QCOMPARE(markup.at(2).content.length, 4);
        QCOMPARE(markup.at(2).markers[0].length, 1);
    }

    void loadsCurrentOmarchyTheme() {
        QTemporaryDir homeDirectory;
        QVERIFY(homeDirectory.isValid());

        const QByteArray originalHome = qgetenv("HOME");
        struct HomeRestorer {
            QByteArray value;
            ~HomeRestorer() { qputenv("HOME", value); }
        } restoreHome{originalHome};
        QVERIFY(qputenv("HOME", homeDirectory.path().toUtf8()));

        const QString themeDirectory = homeDirectory.path()
            + QStringLiteral("/.local/state/omarchy/current/theme");
        QVERIFY(QDir().mkpath(themeDirectory));

        QFile colorsFile(themeDirectory + QStringLiteral("/colors.toml"));
        QVERIFY(colorsFile.open(QIODevice::WriteOnly | QIODevice::Text));
        const QByteArray palette(
            "mode = \"light\"\n"
            "accent = \"#112233\"\n"
            "selection = \"#445566\"\n"
            "background = \"#fefefe\"\n"
            "foreground = \"#101010\"\n");
        QCOMPARE(colorsFile.write(palette), qint64(palette.size()));
        colorsFile.close();

        Backend backend;
        QCOMPARE(backend.themeBackground(), QStringLiteral("#fefefe"));
        QCOMPARE(backend.themeForeground(), QStringLiteral("#101010"));
        QCOMPARE(backend.themeAccent(), QStringLiteral("#112233"));
        QCOMPARE(backend.themeSelection(), QStringLiteral("#445566"));
        QVERIFY(!backend.darkMode());
    }

    void ignoresFileWatcherEventsForSavedContents() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());

        const QString path = directory.filePath(QStringLiteral("first-save.md"));
        Backend backend;
        QSignalSpy externalChangeSpy(&backend, &Backend::externalChangeDetected);

        backend.saveAs(QUrl::fromLocalFile(path));
        QVERIFY(QFileInfo::exists(path));

        QFile sameContents(path);
        QVERIFY(sameContents.open(QIODevice::WriteOnly | QIODevice::Truncate));
        sameContents.close();
        QTest::qWait(100);
        QCOMPARE(externalChangeSpy.count(), 0);

        QFile changedContents(path);
        QVERIFY(changedContents.open(QIODevice::WriteOnly | QIODevice::Truncate));
        QCOMPARE(changedContents.write("changed elsewhere"), qint64(17));
        changedContents.close();
        QTRY_COMPARE(externalChangeSpy.count(), 1);
    }

    void keepsCursorAndSelectionStableAcrossInsertions() {
        const QString mutationsPath = QFINDTESTDATA("../src/EditorMutations.js");
        QVERIFY(!mutationsPath.isEmpty());

        QQmlEngine engine;
        QQmlComponent component(&engine);
        const QByteArray harness = R"QML(
            import QtQuick
            import "EditorMutations.js" as EditorMutations

            TextEdit {
                property string insertionText
                property int insertionCursor
                property string wrappedText
                property int wrappedSelectionStart
                property int wrappedSelectionEnd

                Component.onCompleted: {
                    text = "alpha omega";
                    cursorPosition = 5;
                    EditorMutations.replaceRange(this, 5, 5, "one\r\ntwo");
                    insertionText = text;
                    insertionCursor = cursorPosition;

                    text = "alpha beta omega";
                    select(6, 10);
                    EditorMutations.replaceRange(this, selectionStart, selectionEnd,
                                                 "**beta**", 2, 6);
                    wrappedText = text;
                    wrappedSelectionStart = selectionStart;
                    wrappedSelectionEnd = selectionEnd;
                }
            }
        )QML";
        const QUrl harnessUrl = QUrl::fromLocalFile(
            QFileInfo(mutationsPath).absolutePath() + QStringLiteral("/MutationHarness.qml"));
        component.setData(harness, harnessUrl);
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QScopedPointer<QObject> editor(component.create());
        QVERIFY2(editor, qPrintable(component.errorString()));

        QCOMPARE(editor->property("insertionText").toString(),
                 QStringLiteral("alphaone\ntwo omega"));
        QCOMPARE(editor->property("insertionCursor").toInt(), 12);
        QCOMPARE(editor->property("wrappedText").toString(),
                 QStringLiteral("alpha **beta** omega"));
        QCOMPARE(editor->property("wrappedSelectionStart").toInt(), 8);
        QCOMPARE(editor->property("wrappedSelectionEnd").toInt(), 12);
    }

    void savesAndOpensFromFooterButtons() {
        const QString mainQmlPath = QFINDTESTDATA("../src/Main.qml");
        QVERIFY(!mainQmlPath.isEmpty());

        Backend backend;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
        QQmlComponent component(&engine, QUrl::fromLocalFile(mainQmlPath));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QScopedPointer<QObject> window(component.create());
        QVERIFY2(window, qPrintable(component.errorString()));

        QVERIFY(window->findChild<QObject *>(QStringLiteral("sourceEditor")));
        QVERIFY(!window->findChild<QObject *>(QStringLiteral("renderedPreview")));
        QVERIFY(!window->findChild<QObject *>(QStringLiteral("modeToggle")));

        QObject *saveButton = window->findChild<QObject *>(QStringLiteral("saveButton"));
        QObject *openButton = window->findChild<QObject *>(QStringLiteral("openButton"));
        QObject *historyButton = window->findChild<QObject *>(QStringLiteral("historyButton"));
        QVERIFY(saveButton);
        QVERIFY(openButton);
        QVERIFY(historyButton);

        QSignalSpy saveDialogSpy(&backend, &Backend::saveDialogRequested);
        QVERIFY(QMetaObject::invokeMethod(saveButton, "clicked"));
        QCOMPARE(saveDialogSpy.count(), 1);

        QSignalSpy openDialogSpy(&backend, &Backend::openDialogRequested);
        QVERIFY(QMetaObject::invokeMethod(openButton, "clicked"));
        QCOMPARE(openDialogSpy.count(), 1);
    }

    void scalesTextWithDesktopTextSize() {
        const QString mainQmlPath = QFINDTESTDATA("../src/Main.qml");
        QVERIFY(!mainQmlPath.isEmpty());

        Backend backend;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
        QQmlComponent component(&engine, QUrl::fromLocalFile(mainQmlPath));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QScopedPointer<QObject> window(component.create());
        QVERIFY2(window, qPrintable(component.errorString()));

        QObject *editor = window->findChild<QObject *>(QStringLiteral("sourceEditor"));
        QVERIFY(editor);
        QCOMPARE(editor->property("font").value<QFont>().pixelSize(), 20);

        // `omarchy display text size 16` sets the GNOME factor to 16/12.
        backend.setTextScale(16.0 / 12.0);
        QCOMPARE(window->property("editorFontPixelSize").toInt(), 27);
        QCOMPARE(editor->property("font").value<QFont>().pixelSize(), 27);

        backend.setTextScale(9.0 / 12.0);
        QCOMPARE(window->property("editorFontPixelSize").toInt(), 15);
        QCOMPARE(editor->property("font").value<QFont>().pixelSize(), 15);
    }

    void remembersLastSaveDirectory() {
        QTemporaryDir saveDirectory;
        QVERIFY(saveDirectory.isValid());

        const QString savedPath = saveDirectory.filePath(QStringLiteral("first.md"));
        Backend savedDocument;
        savedDocument.saveAs(QUrl::fromLocalFile(savedPath));

        Backend nextDocument;
        QSignalSpy saveDialogSpy(&nextDocument, &Backend::saveDialogRequested);
        nextDocument.saveAsDialog();
        QCOMPARE(saveDialogSpy.count(), 1);

        const QUrl suggestedUrl = saveDialogSpy.takeFirst().constFirst().toUrl();
        QCOMPARE(QFileInfo(suggestedUrl.toLocalFile()).absolutePath(),
                 saveDirectory.path());
        QCOMPARE(QFileInfo(suggestedUrl.toLocalFile()).fileName(),
                 QStringLiteral("Untitled.md"));

        QSettings().setValue(QStringLiteral("file/lastSaveDirectory"),
                             saveDirectory.filePath(QStringLiteral("missing")));
        Backend fallbackDocument;
        QSignalSpy fallbackDialogSpy(&fallbackDocument, &Backend::saveDialogRequested);
        fallbackDocument.saveAsDialog();
        const QUrl fallbackUrl = fallbackDialogSpy.takeFirst().constFirst().toUrl();
        QCOMPARE(QFileInfo(fallbackUrl.toLocalFile()).absolutePath(), QDir::homePath());
    }

    void autosavesNamedFileAndRestoresCheckpoint() {
        const QString mainQmlPath = QFINDTESTDATA("../src/Main.qml");
        QVERIFY(!mainQmlPath.isEmpty());

        QTemporaryDir directory;
        QVERIFY(directory.isValid());

        Backend backend;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
        QQmlComponent component(&engine, QUrl::fromLocalFile(mainQmlPath));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QScopedPointer<QObject> window(component.create());
        QVERIFY2(window, qPrintable(component.errorString()));

        QObject *editor = window->findChild<QObject *>(QStringLiteral("sourceEditor"));
        QVERIFY(editor);

        editor->setProperty("text", QStringLiteral("first draft"));
        const QString path = directory.filePath(QStringLiteral("note.md"));
        backend.saveAs(QUrl::fromLocalFile(path));
        QVERIFY(QFileInfo::exists(path));
        QCOMPARE(backend.modified(), false);

        editor->setProperty("text", QStringLiteral("second draft"));
        QVERIFY(backend.modified());
        backend.autosaveNow();
        QCOMPARE(backend.modified(), false);

        QFile saved(path);
        QVERIFY(saved.open(QIODevice::ReadOnly | QIODevice::Text));
        QCOMPARE(QString::fromUtf8(saved.readAll()), QStringLiteral("second draft"));

        QVERIFY(backend.checkpoints().size() >= 2);
        const QString oldestId = backend.checkpoints().constLast().toMap()
                                     .value(QStringLiteral("id"))
                                     .toString();
        backend.restoreCheckpoint(oldestId);
        QCOMPARE(editor->property("text").toString(), QStringLiteral("first draft"));
        QVERIFY(backend.modified());
    }

    void checkpointsUntitledWithoutWritingAFile() {
        const QString mainQmlPath = QFINDTESTDATA("../src/Main.qml");
        QVERIFY(!mainQmlPath.isEmpty());

        Backend backend;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
        QQmlComponent component(&engine, QUrl::fromLocalFile(mainQmlPath));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QScopedPointer<QObject> window(component.create());
        QVERIFY2(window, qPrintable(component.errorString()));

        QObject *editor = window->findChild<QObject *>(QStringLiteral("sourceEditor"));
        QVERIFY(editor);
        editor->setProperty("text", QStringLiteral("untitled thoughts"));
        QVERIFY(backend.modified());
        QVERIFY(backend.fileUrl().isEmpty());

        backend.autosaveNow();
        QVERIFY(backend.fileUrl().isEmpty());
        QVERIFY(backend.modified());
        QCOMPARE(backend.status(), QStringLiteral("Checkpointed"));
        QVERIFY(backend.checkpoints().size() >= 1);
        QCOMPARE(backend.checkpoints().constFirst().toMap().value(QStringLiteral("preview")),
                 QStringLiteral("untitled thoughts"));
    }

    void autosavesNamedFileAfterInterval() {
        const QString mainQmlPath = QFINDTESTDATA("../src/Main.qml");
        QVERIFY(!mainQmlPath.isEmpty());

        QTemporaryDir directory;
        QVERIFY(directory.isValid());

        Backend backend;
        backend.setAutosaveInterval(80);
        QCOMPARE(backend.autosaveInterval(), 80);

        QQmlEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
        QQmlComponent component(&engine, QUrl::fromLocalFile(mainQmlPath));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QScopedPointer<QObject> window(component.create());
        QVERIFY2(window, qPrintable(component.errorString()));

        QObject *editor = window->findChild<QObject *>(QStringLiteral("sourceEditor"));
        QVERIFY(editor);
        editor->setProperty("text", QStringLiteral("before"));
        const QString path = directory.filePath(QStringLiteral("timed.md"));
        backend.saveAs(QUrl::fromLocalFile(path));

        editor->setProperty("text", QStringLiteral("after interval"));
        QVERIFY(backend.modified());
        QTRY_COMPARE(backend.modified(), false);

        QFile saved(path);
        QVERIFY(saved.open(QIODevice::ReadOnly | QIODevice::Text));
        QCOMPARE(QString::fromUtf8(saved.readAll()), QStringLiteral("after interval"));
    }

    void opensEachFileInItsOwnTab() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");

        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        QCOMPARE(tabs.count(), 1);
        QVERIFY(!tabs.window->findChild<QObject *>(QStringLiteral("tabStrip"))
                     ->property("visible").toBool());

        // The blank first tab has nothing to lose, so it takes the file.
        tabs.open(first);
        QCOMPARE(tabs.count(), 1);
        QCOMPARE(tabs.backend.fileName(), QStringLiteral("first.md"));

        tabs.open(second);
        QCOMPARE(tabs.count(), 2);
        QCOMPARE(tabs.currentIndex(), 1);
        QCOMPARE(tabs.document(1)->fileName(), QStringLiteral("second.md"));
        QCOMPARE(tabs.backend.fileName(), QStringLiteral("first.md"));
        QVERIFY(tabs.window->property("title").toString().contains(QStringLiteral("second.md")));
        QVERIFY(tabs.window->findChild<QObject *>(QStringLiteral("tabStrip"))
                    ->property("visible").toBool());

        const auto editors = tabs.editors();
        QCOMPARE(editors.size(), 2);
        QCOMPARE(editors.at(0)->property("text").toString(), QStringLiteral("alpha"));
        QCOMPARE(editors.at(1)->property("text").toString(), QStringLiteral("beta"));

        // A file that already has a tab is brought forward, not opened twice.
        tabs.open(first);
        QCOMPARE(tabs.count(), 2);
        QCOMPARE(tabs.currentIndex(), 0);
        QVERIFY(tabs.window->property("title").toString().contains(QStringLiteral("first.md")));

        tabs.call("cycleTab", 1);
        QCOMPARE(tabs.currentIndex(), 1);
        tabs.call("cycleTab", 1);
        QCOMPARE(tabs.currentIndex(), 0);

        tabs.call("closeTab", 1);
        QCOMPARE(tabs.count(), 1);
        QCOMPARE(tabs.document(0), &tabs.backend);
    }

    void drivesTabsFromTheKeyboard() {
        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        auto *window = qobject_cast<QWindow *>(tabs.window.data());
        QVERIFY(window);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));

        QTest::keyClick(window, Qt::Key_T, Qt::ControlModifier);
        QTest::keyClick(window, Qt::Key_T, Qt::ControlModifier);
        QCOMPARE(tabs.count(), 3);
        QCOMPARE(tabs.currentIndex(), 2);

        QTest::keyClick(window, Qt::Key_Tab, Qt::ControlModifier);
        QCOMPARE(tabs.currentIndex(), 0);
        QTest::keyClick(window, Qt::Key_Backtab, Qt::ControlModifier | Qt::ShiftModifier);
        QCOMPARE(tabs.currentIndex(), 2);
        QTest::keyClick(window, Qt::Key_PageUp, Qt::ControlModifier);
        QCOMPARE(tabs.currentIndex(), 1);
        QTest::keyClick(window, Qt::Key_PageDown, Qt::ControlModifier);
        QCOMPARE(tabs.currentIndex(), 2);
        QTest::keyClick(window, Qt::Key_1, Qt::AltModifier);
        QCOMPARE(tabs.currentIndex(), 0);
        QTest::keyClick(window, Qt::Key_3, Qt::AltModifier);
        QCOMPARE(tabs.currentIndex(), 2);

        // Typing lands in the tab that is showing.
        QTest::keyClick(window, Qt::Key_A);
        QCOMPARE(tabs.editors().at(2)->property("text").toString(), QStringLiteral("a"));
        QCOMPARE(tabs.editors().at(0)->property("text").toString(), QString());

        QTest::keyClick(window, Qt::Key_2, Qt::AltModifier);
        QTest::keyClick(window, Qt::Key_W, Qt::ControlModifier);
        QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
        QCOMPARE(tabs.count(), 2);
        QCOMPARE(tabs.editors().at(1)->property("text").toString(), QStringLiteral("a"));
    }

    void keepsEachTabsEditsToItself() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString secondPath = directory.filePath(QStringLiteral("second.md"));
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(secondPath, "beta");

        TabbedWindow tabs;
        tabs.backend.setAutosaveInterval(80);
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.open(first);
        tabs.open(second);
        QCOMPARE(tabs.document(1)->autosaveInterval(), 80);

        tabs.editors().at(1)->setProperty("text", QStringLiteral("beta, reworked"));
        QVERIFY(tabs.document(1)->modified());
        QVERIFY(!tabs.backend.modified());
        QCOMPARE(tabs.editors().at(0)->property("text").toString(), QStringLiteral("alpha"));

        // A tab in the background still saves itself.
        tabs.call("activateTab", 0);
        QTRY_COMPARE(tabs.document(1)->modified(), false);
        QCOMPARE(readFile(secondPath), QStringLiteral("beta, reworked"));
        QCOMPARE(readFile(first.toLocalFile()), QStringLiteral("alpha"));
    }

    void neverSavesATabThatWasDiscarded() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");
        const QUrl third = writeFile(directory.filePath(QStringLiteral("third.md")), "gamma");

        TabbedWindow tabs;
        tabs.backend.setAutosaveInterval(150);
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.open(first);
        tabs.open(second);
        tabs.open(third);
        QCOMPARE(tabs.count(), 3);

        // A later tab's document goes when its tab does.
        tabs.editors().at(1)->setProperty("text", QStringLiteral("beta, regretted"));
        tabs.call("closeTab", 1);
        QCOMPARE(tabs.count(), 3);
        QCOMPARE(tabs.currentIndex(), 1);
        // Answer at once: waiting for the dialog to finish opening would give
        // this test's very short autosave interval time to fire first.
        QVERIFY(tabs.window->property("askingUnsaved").toBool());
        tabs.answerUnsaved("discardRequested");
        QCOMPARE(tabs.count(), 2);

        // The first tab's document belongs to main() and outlives its tab, so
        // it has to be told to stop.
        tabs.editors().at(0)->setProperty("text", QStringLiteral("alpha, regretted"));
        tabs.call("closeTab", 0);
        tabs.answerUnsaved("discardRequested");
        QCOMPARE(tabs.count(), 1);
        QCOMPARE(tabs.document(0)->fileName(), QStringLiteral("third.md"));

        QTest::qWait(500);
        QCOMPARE(readFile(first.toLocalFile()), QStringLiteral("alpha"));
        QCOMPARE(readFile(second.toLocalFile()), QStringLiteral("beta"));
    }

    void asksAboutEveryUnsavedTabBeforeClosing() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");
        const QUrl third = writeFile(directory.filePath(QStringLiteral("third.md")), "gamma");

        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.open(first);
        tabs.open(second);
        tabs.open(third);
        tabs.editors().at(0)->setProperty("text", QStringLiteral("alpha, kept"));
        tabs.editors().at(2)->setProperty("text", QStringLiteral("gamma, dropped"));
        tabs.call("activateTab", 1);

        QVERIFY(QMetaObject::invokeMethod(tabs.window.data(), "close"));
        QVERIFY(tabs.window->property("visible").toBool());
        QCOMPARE(tabs.currentIndex(), 0);
        QVERIFY(tabs.window->property("askingUnsaved").toBool());
        QTRY_VERIFY(tabs.unsavedDialog()->property("opened").toBool());
        QCOMPARE(tabs.unsavedDialog()->property("fileName").toString(), QStringLiteral("first.md"));

        // Saving the first moves the question on to the next unsaved tab.
        tabs.answerUnsaved("saveRequested");
        QCOMPARE(readFile(first.toLocalFile()), QStringLiteral("alpha, kept"));
        QVERIFY(tabs.window->property("visible").toBool());
        QCOMPARE(tabs.currentIndex(), 2);
        QVERIFY(tabs.window->property("askingUnsaved").toBool());
        QTRY_VERIFY(tabs.unsavedDialog()->property("opened").toBool());
        QCOMPARE(tabs.unsavedDialog()->property("fileName").toString(), QStringLiteral("third.md"));

        tabs.answerUnsaved("discardRequested");
        QTRY_VERIFY(!tabs.window->property("visible").toBool());
        QCOMPARE(readFile(third.toLocalFile()), QStringLiteral("gamma"));
    }

    void cancellingTheQuestionKeepsTheWindowOpen() {
        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.call("newTab");
        tabs.editors().at(1)->setProperty("text", QStringLiteral("not done yet"));

        QVERIFY(QMetaObject::invokeMethod(tabs.window.data(), "close"));
        QVERIFY(tabs.window->property("askingUnsaved").toBool());
        QTRY_VERIFY(tabs.unsavedDialog()->property("opened").toBool());
        QVERIFY(QMetaObject::invokeMethod(tabs.unsavedDialog(), "reject"));

        QVERIFY(tabs.window->property("visible").toBool());
        QCOMPARE(tabs.count(), 2);
        QCOMPARE(tabs.window->property("pendingAction").toString(), QString());
        QCOMPARE(tabs.editors().at(1)->property("text").toString(), QStringLiteral("not done yet"));
    }

    void asksAboutFilesChangedElsewhereOneTabAtATime() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");
        const QUrl third = writeFile(directory.filePath(QStringLiteral("third.md")), "gamma");

        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.open(first);
        tabs.open(second);
        tabs.open(third);
        QObject *dialog = tabs.window->findChild<QObject *>(QStringLiteral("externalChangeDialog"));
        QVERIFY(dialog);

        // A sync or a git checkout rewrites two background files together.
        writeFile(first.toLocalFile(), "alpha from elsewhere");
        writeFile(second.toLocalFile(), "beta from elsewhere");

        QTRY_VERIFY(tabs.window->property("askingExternal").toBool());
        const int firstAsked = tabs.currentIndex();
        QVERIFY(firstAsked == 0 || firstAsked == 1);
        QTRY_VERIFY(dialog->property("opened").toBool());

        // While the question stands, the tabs hold still.
        tabs.call("activateTab", 2);
        QCOMPARE(tabs.currentIndex(), firstAsked);

        QMetaObject::invokeMethod(dialog, "close");
        QMetaObject::invokeMethod(dialog, "reloadRequested");

        // Then the other file gets its turn, in its own tab.
        const int secondAsked = 1 - firstAsked;
        QTRY_COMPARE(tabs.currentIndex(), secondAsked);
        QTRY_VERIFY(dialog->property("opened").toBool());
        QMetaObject::invokeMethod(dialog, "close");
        QMetaObject::invokeMethod(dialog, "reloadRequested");
        QTRY_VERIFY(!tabs.window->property("askingExternal").toBool());

        QCOMPARE(tabs.editors().at(0)->property("text").toString(),
                 QStringLiteral("alpha from elsewhere"));
        QCOMPARE(tabs.editors().at(1)->property("text").toString(),
                 QStringLiteral("beta from elsewhere"));
        QCOMPARE(tabs.editors().at(2)->property("text").toString(), QStringLiteral("gamma"));
    }

    void freesTheTabsWhenASaveFails() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString lockedDirectory = directory.filePath(QStringLiteral("locked"));
        QVERIFY(QDir().mkpath(lockedDirectory));
        const QUrl first = writeFile(lockedDirectory + QStringLiteral("/first.md"), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");

        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.open(first);
        tabs.open(second);
        tabs.editors().at(0)->setProperty("text", QStringLiteral("alpha, unsaveable"));

        // An atomic save writes a temporary file beside the target first.
        QFile::setPermissions(lockedDirectory, QFileDevice::ReadOwner | QFileDevice::ExeOwner);
        struct Unlock {
            QString path;
            ~Unlock() { QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner
                                                        | QFileDevice::ExeOwner); }
        } unlock{lockedDirectory};

        tabs.call("closeTab", 0);
        tabs.answerUnsaved("saveRequested");

        // Nothing closed, the text is still there, and the tabs are usable.
        QCOMPARE(tabs.count(), 2);
        QVERIFY(tabs.backend.modified());
        QVERIFY(!tabs.window->property("tabsLocked").toBool());
        tabs.call("activateTab", 1);
        QCOMPARE(tabs.currentIndex(), 1);
        QCOMPARE(tabs.editors().at(0)->property("text").toString(),
                 QStringLiteral("alpha, unsaveable"));
    }

    void givesEveryCrashSnapshotATab() {
        const QDir state(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
        QVERIFY(QDir().mkpath(state.path()));
        writeFile(state.filePath(QStringLiteral("recovery-0.json")),
                  "{\"fileUrl\":\"\",\"text\":\"first lost draft\"}");
        writeFile(state.filePath(QStringLiteral("recovery-3.json")),
                  "{\"fileUrl\":\"\",\"text\":\"second lost draft\"}");

        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        QCOMPARE(tabs.count(), 2);
        QCOMPARE(tabs.currentIndex(), 0);

        QStringList recovered;
        for (QObject *editor : tabs.editors())
            recovered.append(editor->property("text").toString());
        recovered.sort();
        QCOMPARE(recovered, QStringList({QStringLiteral("first lost draft"),
                                         QStringLiteral("second lost draft")}));
        QVERIFY(tabs.document(0)->modified());
        QVERIFY(tabs.document(1)->modified());
    }

    void snapshotsEachUnsavedTabSeparately() {
        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.call("newTab");
        tabs.editors().at(0)->setProperty("text", QStringLiteral("one draft"));
        tabs.editors().at(1)->setProperty("text", QStringLiteral("another draft"));

        const QDir state(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
        QTRY_COMPARE(state.entryList({QStringLiteral("recovery-*.json")}, QDir::Files).size(), 2);

        QStringList snapshots;
        for (const QString &name : state.entryList({QStringLiteral("recovery-*.json")}, QDir::Files)) {
            snapshots.append(QJsonDocument::fromJson(readFile(state.filePath(name)).toUtf8())
                                 .object().value(QStringLiteral("text")).toString());
        }
        snapshots.sort();
        QCOMPARE(snapshots, QStringList({QStringLiteral("another draft"),
                                         QStringLiteral("one draft")}));
    }

    void bringsBackLastSessionsTabs() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");
        const QUrl third = writeFile(directory.filePath(QStringLiteral("third.md")), "gamma");
        {
            TabbedWindow tabs;
            QVERIFY2(tabs.load(), qPrintable(tabs.error));
            tabs.call("restoreSession");
            QCOMPARE(tabs.count(), 1);
            tabs.open(first);
            tabs.open(second);
            tabs.open(third);
            tabs.call("newTab");
            tabs.call("activateTab", 1);
        }

        TabbedWindow next;
        QVERIFY2(next.load(), qPrintable(next.error));
        next.call("restoreSession");
        // The blank tab had nothing in it to bring back.
        QCOMPARE(next.count(), 3);
        QCOMPARE(next.title(0), QStringLiteral("first.md"));
        QCOMPARE(next.title(1), QStringLiteral("second.md"));
        QCOMPARE(next.title(2), QStringLiteral("third.md"));
        QCOMPARE(next.currentIndex(), 1);
        QCOMPARE(next.editors().at(2)->property("text").toString(), QStringLiteral("gamma"));
        QVERIFY(!next.document(0)->modified());

        // A tab closed on purpose stays closed next time.
        next.call("closeTab", 0);
        next.window.reset();
        TabbedWindow last;
        QVERIFY2(last.load(), qPrintable(last.error));
        QVERIFY(!last.backend.claimSession());
    }

    void leavesTheSessionToTheWindowThatOwnsIt() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");
        const QUrl other = writeFile(directory.filePath(QStringLiteral("other.md")), "omega");
        {
            TabbedWindow owner;
            QVERIFY2(owner.load(), qPrintable(owner.error));
            owner.call("restoreSession");
            owner.open(first);
            owner.open(second);

            // A second window while the first is up: blank, and its tabs are
            // not what gets remembered.
            TabbedWindow side;
            QVERIFY2(side.load(), qPrintable(side.error));
            side.call("restoreSession");
            QCOMPARE(side.count(), 1);
            QVERIFY(side.backend.fileUrl().isEmpty());
            side.open(other);

            // Nor are those of a window that was opened for a file and never asked.
            TabbedWindow forFile;
            QVERIFY2(forFile.load(), qPrintable(forFile.error));
            forFile.open(other);
        }

        TabbedWindow next;
        QVERIFY2(next.load(), qPrintable(next.error));
        next.call("restoreSession");
        QCOMPARE(next.count(), 2);
        QCOMPARE(next.title(0), QStringLiteral("first.md"));
        QCOMPARE(next.title(1), QStringLiteral("second.md"));
    }

    void keepsADiscardedFilesPlaceInTheSession() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");
        const QUrl third = writeFile(directory.filePath(QStringLiteral("third.md")), "gamma");
        {
            TabbedWindow tabs;
            QVERIFY2(tabs.load(), qPrintable(tabs.error));
            tabs.call("restoreSession");
            tabs.open(first);
            tabs.open(second);
            tabs.open(third);
            tabs.editors().at(0)->setProperty("text", QStringLiteral("alpha, regretted"));
            tabs.call("activateTab", 1);

            QVERIFY(QMetaObject::invokeMethod(tabs.window.data(), "close"));
            QCOMPARE(tabs.currentIndex(), 0);
            tabs.answerUnsaved("discardRequested");
            QTRY_VERIFY(!tabs.window->property("visible").toBool());
        }

        // The edits went; the file keeps its tab, and the tab in use at the
        // time is the one that comes back in front.
        TabbedWindow next;
        QVERIFY2(next.load(), qPrintable(next.error));
        next.call("restoreSession");
        QCOMPARE(next.count(), 3);
        QCOMPARE(next.title(0), QStringLiteral("first.md"));
        QCOMPARE(next.title(1), QStringLiteral("second.md"));
        QCOMPARE(next.currentIndex(), 1);
        QCOMPARE(next.editors().at(0)->property("text").toString(), QStringLiteral("alpha"));
    }

    void forgetsADiscardedTabWhenTheCloseIsCalledOff() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");
        {
            TabbedWindow tabs;
            QVERIFY2(tabs.load(), qPrintable(tabs.error));
            tabs.call("restoreSession");
            tabs.open(first);
            tabs.open(second);
            tabs.editors().at(0)->setProperty("text", QStringLiteral("alpha, regretted"));
            tabs.editors().at(1)->setProperty("text", QStringLiteral("beta, still going"));

            QVERIFY(QMetaObject::invokeMethod(tabs.window.data(), "close"));
            tabs.answerUnsaved("discardRequested");
            QCOMPARE(tabs.count(), 1);
            QVERIFY(tabs.window->property("askingUnsaved").toBool());
            QVERIFY(QMetaObject::invokeMethod(tabs.unsavedDialog(), "reject"));
            QVERIFY(tabs.window->property("visible").toBool());
            QVERIFY(!tabs.window->property("closingWindow").toBool());
            tabs.document(0)->save();
        }

        // The window stayed open without the first file, so that is the session.
        TabbedWindow next;
        QVERIFY2(next.load(), qPrintable(next.error));
        next.call("restoreSession");
        QCOMPARE(next.count(), 1);
        QCOMPARE(next.title(0), QStringLiteral("second.md"));
        QCOMPARE(next.editors().at(0)->property("text").toString(),
                 QStringLiteral("beta, still going"));
    }

    void reopensARecoveredFileOnlyOnce() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QUrl first = writeFile(directory.filePath(QStringLiteral("first.md")), "alpha");
        const QUrl second = writeFile(directory.filePath(QStringLiteral("second.md")), "beta");
        const QUrl gone = QUrl::fromLocalFile(directory.filePath(QStringLiteral("gone.md")));

        // What a crash leaves: the session, and a snapshot of the unsaved tab.
        const QDir state(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
        QVERIFY(QDir().mkpath(state.path()));
        const QJsonObject session{
            {QStringLiteral("files"), QJsonArray{first.toLocalFile(), gone.toLocalFile(),
                                                 second.toLocalFile()}},
            {QStringLiteral("current"), second.toLocalFile()}};
        writeFile(state.filePath(QStringLiteral("contrawrite-session.json")),
                  QJsonDocument(session).toJson());
        const QJsonObject snapshot{{QStringLiteral("fileUrl"), first.toString()},
                                   {QStringLiteral("text"), QStringLiteral("alpha, unsaved")}};
        writeFile(state.filePath(QStringLiteral("recovery-0.json")),
                  QJsonDocument(snapshot).toJson());

        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.call("restoreSession");

        // One tab for first.md, holding the recovered text; gone.md is skipped.
        QCOMPARE(tabs.count(), 2);
        QCOMPARE(tabs.title(0), QStringLiteral("first.md"));
        QCOMPARE(tabs.editors().at(0)->property("text").toString(),
                 QStringLiteral("alpha, unsaved"));
        QVERIFY(tabs.document(0)->modified());
        QCOMPARE(tabs.title(1), QStringLiteral("second.md"));
        QCOMPARE(tabs.currentIndex(), 1);
    }

    void namesTabsSoTheyCanBeToldApart() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        QVERIFY(QDir(directory.path()).mkpath(QStringLiteral("atlas")));
        QVERIFY(QDir(directory.path()).mkpath(QStringLiteral("borealis")));
        const QUrl atlas = writeFile(directory.filePath(QStringLiteral("atlas/README.md")), "a");
        const QUrl borealis = writeFile(directory.filePath(QStringLiteral("borealis/README.md")), "b");
        const QUrl notes = writeFile(directory.filePath(QStringLiteral("atlas/notes.md")), "n");

        TabbedWindow tabs;
        QVERIFY2(tabs.load(), qPrintable(tabs.error));
        tabs.open(atlas);
        QCOMPARE(tabs.title(0), QStringLiteral("README.md"));

        tabs.open(borealis);
        tabs.open(notes);
        QCOMPARE(tabs.title(0), QStringLiteral("atlas/README.md"));
        QCOMPARE(tabs.title(1), QStringLiteral("borealis/README.md"));
        QCOMPARE(tabs.title(2), QStringLiteral("notes.md"));

        // A tab with no file yet goes by its first line.
        tabs.call("newTab");
        QCOMPARE(tabs.title(3), QStringLiteral("Untitled"));
        tabs.editors().at(3)->setProperty("text", QStringLiteral("# Launch plan\n\nBody"));
        QCOMPARE(tabs.title(3), QStringLiteral("Launch plan"));
    }

private:
    // Main.qml around a first backend, the way main() sets it up.
    struct TabbedWindow {
        Backend backend;
        QQmlEngine engine;
        QScopedPointer<QObject> window;
        QString error;

        bool load() {
            const QString mainQmlPath = QFINDTESTDATA("../src/Main.qml");
            engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
            QQmlComponent component(&engine, QUrl::fromLocalFile(mainQmlPath));
            window.reset(component.create());
            error = component.errorString();
            return !window.isNull();
        }

        QVariant call(const char *function, const QVariant &argument = QVariant()) {
            QVariant result;
            if (argument.isValid()) {
                QMetaObject::invokeMethod(window.data(), function,
                                          Q_RETURN_ARG(QVariant, result),
                                          Q_ARG(QVariant, argument));
            } else {
                QMetaObject::invokeMethod(window.data(), function,
                                          Q_RETURN_ARG(QVariant, result));
            }
            // Closed tabs are destroyed on the next turn of the event loop.
            QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
            return result;
        }

        void open(const QUrl &url) { call("requestOpen", url); }
        int count() const { return window->property("tabCount").toInt(); }
        int currentIndex() const { return window->property("currentIndex").toInt(); }
        QString title(int index) { return call("tabTitle", index).toString(); }
        Backend *document(int index) {
            return qobject_cast<Backend *>(call("documentAt", index).value<QObject *>());
        }
        QList<QObject *> editors() const {
            return window->findChildren<QObject *>(QStringLiteral("sourceEditor"));
        }
        QObject *unsavedDialog() const {
            return window->findChild<QObject *>(QStringLiteral("unsavedChangesDialog"));
        }
        // What the dialog's buttons do: close it, then announce the choice.
        void answerUnsaved(const char *choice) {
            QMetaObject::invokeMethod(unsavedDialog(), "close");
            QMetaObject::invokeMethod(unsavedDialog(), choice);
            QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
        }
    };

    static QUrl writeFile(const QString &path, const QByteArray &contents) {
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)
                || file.write(contents) != contents.size())
            return {};
        return QUrl::fromLocalFile(path);
    }

    static QString readFile(const QString &path) {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
    }

    QTemporaryDir m_settingsDirectory;
};

QTEST_MAIN(OmawriteTest)
#include "tst_omawrite.moc"
