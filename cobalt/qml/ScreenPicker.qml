import QtQuick

// The screen-share source chooser. When Teams calls getDisplayMedia(),
// QtWebEngine emits WebEngineView.desktopMediaRequested; Main hands the request
// to the Media controller (Python), which exposes the screen/window models and
// resolves the pick by row. This file is pure presentation — it reads
// Media.screens / Media.windows and calls Media.selectScreen/selectWindow/cancel.
//
// THIS is the phase-0 gate from the plan: if a picked source actually appears
// in the call, the Qt path is proven. If it never captures, that's the signal
// to fall back to an Electron shell.
Item {
    id: root
    visible: Media.active
    focus: Media.active

    Keys.onEscapePressed: Media.cancel()

    // scrim — swallows stray clicks; a click on it cancels
    Rectangle {
        anchors.fill: parent
        color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: Media.cancel() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width - 80, 720)
        height: Math.min(root.height - 80, 560)
        radius: Theme.radius
        color: Theme.card
        border.color: Theme.border
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                text: "share your screen"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 16
                font.bold: true
            }

            Flickable {
                width: parent.width
                height: parent.height - 84
                contentHeight: sources.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: sources
                    width: parent.width
                    spacing: 16

                    SourceSection {
                        width: sources.width
                        label: "screens"
                        model: Media.screens
                        onChosen: (i) => Media.selectScreen(i)
                    }
                    SourceSection {
                        width: sources.width
                        label: "windows"
                        model: Media.windows
                        onChosen: (i) => Media.selectWindow(i)
                    }
                }
            }

            // footer
            Rectangle { width: parent.width; height: 1; color: Theme.divider }
            Row {
                anchors.right: parent.right
                spacing: 8
                Rectangle {
                    width: cancelText.implicitWidth + 26; height: 30
                    radius: Theme.radiusSm
                    color: cancelHover.containsMouse ? Theme.glassSoft : "transparent"
                    border.color: Theme.border; border.width: 1
                    Text {
                        id: cancelText
                        anchors.centerIn: parent; text: "cancel"
                        color: Theme.subtext; font.family: Theme.font; font.pixelSize: 12
                    }
                    MouseArea {
                        id: cancelHover; anchors.fill: parent
                        hoverEnabled: true; onClicked: Media.cancel()
                    }
                }
            }
        }
    }

    // a titled grid of source tiles, driven by one of Media's models
    component SourceSection: Column {
        id: section
        property string label
        property var model
        signal chosen(int index)
        spacing: 8
        visible: repeater.count > 0

        Text {
            text: section.label + "  ·  " + repeater.count
            color: Theme.subtext
            font.family: Theme.font; font.pixelSize: 11
        }
        Flow {
            width: section.width
            spacing: 8
            Repeater {
                id: repeater
                model: section.model
                delegate: Rectangle {
                    id: tile
                    required property int index
                    required property var model
                    width: 150; height: 92
                    radius: Theme.radiusSm
                    color: tileHover.containsMouse ? Theme.sel : Theme.glassSoft
                    border.color: tileHover.containsMouse ? Theme.accent : Theme.border
                    border.width: 1
                    Text {
                        anchors.fill: parent
                        anchors.margins: 10
                        text: tile.model.display !== undefined ? tile.model.display
                                                               : (section.label + " " + (tile.index + 1))
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 12
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    MouseArea {
                        id: tileHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: section.chosen(tile.index)
                    }
                }
            }
        }
    }
}
