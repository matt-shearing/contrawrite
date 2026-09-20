pragma Singleton
import QtQml

// The window's own `backend` property (the current tab's document) hides the
// `backend` context property from everything inside Main.qml. A singleton is
// created in the engine's root context, outside the window, so it still sees
// the context property and can hand it over as the first tab's document.
QtObject {
    readonly property var instance: backend
}
