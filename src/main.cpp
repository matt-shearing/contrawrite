#include <QFont>
#include <QFontDatabase>
#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickStyle>
#include <QUrl>
#include <QWindow>
#include <QFile>
#include <QFileInfo>

#include "backend.h"
#include "cli.h"
#include "systemtheme.h"

#define OMAWRITE_VERSION "0.7.2"

int main(int argc, char *argv[]) {
    // Answered before the application exists, so they need no display.
    if (const std::optional<int> exitCode =
            Cli::handleArguments(argc, argv, QStringLiteral(OMAWRITE_VERSION)))
        return *exitCode;

    // Omarchy asks Qt for GTK 3 dialogs, which run inside this process, and a
    // long-standing GTK 3 file chooser assertion aborts the whole app, unsaved
    // text and all. The desktop portal shows the same chooser from a process
    // of its own.
    if (qgetenv("QT_QPA_PLATFORMTHEME") == "gtk3")
        qputenv("QT_QPA_PLATFORMTHEME", "xdgdesktopportal");

    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("omawrite"));
    app.setApplicationDisplayName(QStringLiteral("Contrawrite"));
    app.setApplicationVersion(QStringLiteral(OMAWRITE_VERSION));
    app.setDesktopFileName(QStringLiteral("contrawrite"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("contrawrite")));

    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/IBMPlexMono-Regular.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/IBMPlexMono-Italic.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/IBMPlexMono-Bold.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/IBMPlexMono-BoldItalic.ttf"));
    app.setOrganizationName(QStringLiteral("Omacom"));
    app.setOrganizationDomain(QStringLiteral("omacom.io"));

    QQuickStyle::setStyle(QStringLiteral("Material"));

    Backend backend(&app);
    SystemTheme systemTheme(&app);
    backend.setDarkMode(systemTheme.darkMode());
    QObject::connect(&systemTheme, &SystemTheme::darkModeChanged, &backend,
                     &Backend::setDarkMode);

    // Carry the text scale into the default font, so the chrome that inherits
    // it (dialog titles, buttons) grows along with the writing area.
    const QFont interfaceFont(QStringLiteral("IBM Plex Mono"));
    const qreal basePointSize = interfaceFont.pointSizeF() > 0
        ? interfaceFont.pointSizeF()
        : app.font().pointSizeF();
    const auto applyInterfaceFont = [&app, interfaceFont, basePointSize](qreal textScale) {
        QFont scaled = interfaceFont;
        scaled.setPointSizeF(basePointSize * textScale);
        app.setFont(scaled);
    };

    // The desktop sets the baseline; the backend folds the user's own text
    // size into it and reports the total.
    backend.setDesktopTextScale(systemTheme.textScale());
    applyInterfaceFont(backend.textScale());
    QObject::connect(&systemTheme, &SystemTheme::textScaleChanged, &backend,
                     &Backend::setDesktopTextScale);
    QObject::connect(&backend, &Backend::textScaleChanged, &app,
                     [&backend, applyInterfaceFont]() {
        applyInterfaceFont(backend.textScale());
    });

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app,
                     [](const QList<QQmlError> &warnings) {
        for (const QQmlError &warning : warnings)
            qWarning().noquote() << warning.toString();
    });
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);

    engine.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Could not load the Contrawrite interface; resource available:"
                    << QFile::exists(QStringLiteral(":/Main.qml"));
        return -1;
    }

    QObject *window = engine.rootObjects().constFirst();
    backend.setParentWindow(qobject_cast<QWindow *>(window));

    // Launched on its own, Contrawrite brings back the tabs it had last time.
    // Asked for particular files, or for a new window, it opens exactly that
    // and leaves the remembered tabs to the window that owns them.
    QStringList files;
    for (const QString &arg : app.arguments().mid(1)) {
        if (arg != QStringLiteral("--new-window"))
            files.append(QFileInfo(arg).absoluteFilePath());
    }
    if (files.isEmpty()) {
        QMetaObject::invokeMethod(window, "restoreSession");
    } else if (files.size() == 1 && !QFileInfo::exists(files.at(0))) {
        // `contrawrite new.md` starts a blank document the first save writes
        // there, the same as Omawrite. An existing path takes a tab below.
        backend.openOrStartFile(QUrl::fromLocalFile(files.at(0)));
    } else {
        for (const QString &path : files) {
            QMetaObject::invokeMethod(window, "requestOpen",
                                      Q_ARG(QVariant, QUrl::fromLocalFile(path)));
        }
    }

    return app.exec();
}
