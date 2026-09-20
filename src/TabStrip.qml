import QtQuick
import QtQuick.Controls

// The row of tabs above the page. It hides while the window holds a single
// document, so one file on its own looks just as it did before tabs existed.
Item {
    id: strip

    property var pages: []
    property Item currentPage: null
    property color pageColor: "#101010"
    property color textColor: "#eeeeee"
    property color accentColor: "#5584aa"
    property real textScale: 1

    signal activateRequested(int index)
    signal closeRequested(int index)
    signal newTabRequested()

    // Tab names have to be read at a glance, so they sit between the page's
    // text and the much fainter grey of the footer.
    readonly property color quietColor: tint(textColor, 0.6)
    readonly property int addButtonWidth: scaled(34)
    readonly property real tabWidth: Math.max(scaled(72), Math.min(scaled(220),
        (width - addButtonWidth) / Math.max(1, pages.length)))

    visible: pages.length > 1
    height: scaled(34)
    clip: true

    function scaled(pixels) {
        return Math.max(1, Math.round(pixels * textScale));
    }

    function tint(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function localPath(page) {
        return decodeURIComponent(page.backend.fileUrl.toString()).replace(/^file:\/\//, "");
    }

    // Two projects each have a README.md. When names collide, lead with the
    // folder so the tabs can be told apart.
    function titleFor(page) {
        var path = localPath(page);
        if (path === "")
            return page.headline !== "" ? page.headline : "Untitled";

        var name = page.backend.fileName;
        for (var i = 0; i < pages.length; ++i) {
            if (pages[i] !== page && pages[i].backend.fileName === name) {
                var parts = path.split("/");
                return parts.length > 1 ? parts[parts.length - 2] + "/" + name : name;
            }
        }
        return name;
    }

    Rectangle {
        anchors.fill: parent
        color: strip.pageColor
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: strip.tint(strip.textColor, 0.12)
    }

    Row {
        id: tabRow
        height: parent.height

        Repeater {
            model: strip.pages

            delegate: Item {
                id: tab

                required property int index
                required property var modelData
                readonly property bool current: modelData === strip.currentPage
                readonly property bool hovered: tabArea.containsMouse || closeArea.containsMouse

                objectName: "tab" + index
                width: strip.tabWidth
                height: tabRow.height

                ToolTip.visible: tabArea.containsMouse && ToolTip.text !== ""
                ToolTip.delay: 700
                ToolTip.text: strip.localPath(modelData)

                Rectangle {
                    anchors.fill: parent
                    color: strip.tint(strip.textColor, tab.hovered && !tab.current ? 0.06 : 0)
                }

                MouseArea {
                    id: tabArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.MiddleButton)
                            strip.closeRequested(tab.index);
                        else
                            strip.activateRequested(tab.index);
                    }
                }

                Label {
                    anchors.left: parent.left
                    anchors.right: closeLabel.left
                    anchors.leftMargin: strip.scaled(14)
                    anchors.rightMargin: strip.scaled(4)
                    anchors.verticalCenter: parent.verticalCenter
                    text: (tab.modelData.backend.modified ? "• " : "") + strip.titleFor(tab.modelData)
                    color: tab.current ? strip.textColor : strip.quietColor
                    elide: Text.ElideRight
                    font.family: "iA Writer Mono S"
                    font.pixelSize: strip.scaled(12)
                }

                Label {
                    id: closeLabel
                    anchors.right: parent.right
                    anchors.rightMargin: strip.scaled(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: strip.scaled(14)
                    horizontalAlignment: Text.AlignHCenter
                    text: "×"
                    opacity: tab.hovered || tab.current ? 1 : 0
                    color: closeArea.containsMouse ? strip.textColor : strip.quietColor
                    font.family: "iA Writer Mono S"
                    font.pixelSize: strip.scaled(14)

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -strip.scaled(5)
                        hoverEnabled: true
                        onClicked: strip.closeRequested(tab.index)
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: strip.scaled(2)
                    color: strip.accentColor
                    visible: tab.current
                }
            }
        }

        Item {
            objectName: "newTabButton"
            width: strip.addButtonWidth
            height: tabRow.height

            ToolTip.visible: addArea.containsMouse
            ToolTip.delay: 700
            ToolTip.text: "New tab"

            Label {
                anchors.centerIn: parent
                text: "+"
                color: addArea.containsMouse ? strip.textColor : strip.quietColor
                font.family: "iA Writer Mono S"
                font.pixelSize: strip.scaled(15)
            }

            MouseArea {
                id: addArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: strip.newTabRequested()
            }
        }
    }
}
