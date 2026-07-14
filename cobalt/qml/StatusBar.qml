import QtQuick

// Slim vim status line: a mode pill on the left when you're not in normal, the
// pending key sequence and find count on the right. Glass, like the titlebar.
Rectangle {
    id: bar
    property string findCount: ""

    color: Theme.bg
    Rectangle {              // hairline on top
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: Theme.divider
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 10
        spacing: 8

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: Vim.mode !== "normal"
            width: modeLabel.implicitWidth + 12
            height: 16
            radius: 4
            color: Vim.mode === "insert" ? Theme.accentSoft
                 : Vim.mode === "hint" ? Theme.sel : Theme.glassSoft
            Text {
                id: modeLabel
                anchors.centerIn: parent
                text: Vim.mode.toUpperCase()
                color: Theme.accent
                font.pixelSize: 10
                font.bold: true
                font.family: Theme.font
            }
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 10
        spacing: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: bar.findCount
            visible: bar.findCount !== ""
            color: Theme.subtext
            font.pixelSize: 11
            font.family: Theme.font
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Vim.pending
            color: Theme.accent2
            font.pixelSize: 11
            font.bold: true
            font.family: Theme.font
        }
    }
}
