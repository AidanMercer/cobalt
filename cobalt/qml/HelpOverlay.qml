import QtQuick

// The `h` sheet: every bind, grouped, straight off Vim.helpModel — which is the
// live bind table joined to the command registry's own descriptions. Nothing is
// hardcoded here, so a rebind (or a new command with a desc + group) shows up
// without touching this file. Pure presentation; the KeyController owns the
// mode and closes it on any key.
Item {
    id: root
    visible: Vim.mode === "help"

    // group columns are a fixed width: a divider that spanned the Column's
    // implicit width would feed back into the width that produced it
    readonly property int colWidth: 236

    // helpModel arrives flat and pre-sorted by group; fold it into columns
    // while keeping that order.
    readonly property var groups: {
        var out = [], seen = {}
        var m = visible ? Vim.helpModel : []
        for (var i = 0; i < m.length; i++) {
            var g = m[i].group
            if (seen[g] === undefined) {
                seen[g] = out.length
                out.push({ name: g, rows: [] })
            }
            out[seen[g]].rows.push(m[i])
        }
        return out
    }

    // scrim — swallows stray clicks; a click anywhere dismisses, like any key
    Rectangle {
        anchors.fill: parent
        color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: Vim.setMode("normal") }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width - 64, sheet.implicitWidth + 44)
        height: Math.min(root.height - 64, sheet.implicitHeight + 44)
        radius: Theme.radius
        color: Theme.card
        border.color: Theme.border
        border.width: 1

        Column {
            id: sheet
            anchors.centerIn: parent
            spacing: 16

            Row {
                spacing: 10
                Text {
                    id: title
                    text: "keys"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    anchors.baseline: title.baseline
                    text: "any key closes"
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }

            Grid {
                columns: 2
                columnSpacing: 30
                rowSpacing: 18

                Repeater {
                    model: root.groups
                    delegate: Column {
                        id: col
                        required property var modelData
                        width: root.colWidth
                        spacing: 6

                        Text {
                            text: col.modelData.name
                            color: Theme.accent2
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Rectangle {
                            width: col.width
                            height: 1
                            color: Theme.divider
                        }
                        Repeater {
                            model: col.modelData.rows
                            delegate: Row {
                                id: bindRow
                                required property var modelData
                                width: col.width
                                spacing: 10

                                Rectangle {
                                    width: 48
                                    height: 18
                                    radius: 4
                                    color: Theme.glassSoft
                                    Text {
                                        anchors.centerIn: parent
                                        text: bindRow.modelData.key
                                        color: Theme.accent
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: bindRow.width - 58
                                    text: bindRow.modelData.desc
                                    color: Theme.subtext
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
