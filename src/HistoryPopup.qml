import QtQuick
import QtQuick.Controls

Popup {
    id: root

    property Item anchorItem
    property bool darkMode: true
    property color textColor: darkMode ? "#d0d0d0" : "#42464c"
    property color strongTextColor: darkMode ? "#eeeeee" : "#222324"
    property color mutedColor: darkMode ? "#909191" : "#aeb1b5"
    property real textScale: 1
    property var checkpoints: []

    signal restoreRequested(string id)

    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: Math.round(280 * textScale)
    height: Math.round(Math.min(contentColumn.implicitHeight, 280 * textScale))
    x: {
        if (!anchorItem || !parent)
            return 12
        return anchorItem.mapToItem(parent, 0, 0).x
    }
    y: {
        if (!anchorItem || !parent)
            return 12
        return anchorItem.mapToItem(parent, 0, 0).y - height - Math.round(10 * textScale)
    }

    onAboutToShow: backend.refreshCheckpoints()

    background: Rectangle {
        color: root.darkMode ? "#1a1a1a" : "#ffffff"
        border.color: root.darkMode ? "#343434" : "#d8d8d8"
        radius: 0
    }

    contentItem: Item {
        Column {
            id: contentColumn
            width: root.width
            spacing: 0

            Label {
                text: "Checkpoints"
                color: root.strongTextColor
                font.family: "iA Writer Mono S"
                font.pixelSize: Math.round(12 * root.textScale)
                font.bold: true
                leftPadding: 12
                rightPadding: 12
                topPadding: 10
                bottomPadding: 8
            }

            Label {
                width: parent.width
                visible: root.checkpoints.length === 0
                text: "Nothing stored yet.\nEdits are kept every 30 seconds."
                color: root.mutedColor
                wrapMode: Text.Wrap
                font.family: "iA Writer Mono S"
                font.pixelSize: Math.round(11 * root.textScale)
                leftPadding: 12
                rightPadding: 12
                bottomPadding: 12
            }

            ListView {
                id: checkpointList
                objectName: "checkpointList"
                width: parent.width
                height: Math.min(contentHeight, Math.round(232 * root.textScale))
                visible: root.checkpoints.length > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.checkpoints

                delegate: Item {
                    width: checkpointList.width
                    height: Math.round(46 * root.textScale)

                    Rectangle {
                        anchors.fill: parent
                        color: hitArea.containsMouse
                            ? (root.darkMode ? "#242424" : "#f2f2f2")
                            : "transparent"
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 2

                        Label {
                            width: parent.width
                            text: modelData.when
                            color: root.mutedColor
                            font.family: "iA Writer Mono S"
                            font.pixelSize: Math.round(10 * root.textScale)
                        }

                        Label {
                            width: parent.width
                            text: modelData.preview
                            color: root.strongTextColor
                            elide: Text.ElideRight
                            font.family: "iA Writer Mono S"
                            font.pixelSize: Math.round(12 * root.textScale)
                        }
                    }

                    MouseArea {
                        id: hitArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.restoreRequested(modelData.id)
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
