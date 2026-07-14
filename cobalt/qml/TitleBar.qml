import QtQuick

// The one piece of chrome that's fully ours: a world80 glass strip above the
// Teams view. Drag it to move the (frameless) window; the buttons minimise and
// close. "Close" honours Config.close_to_background — it hides so calls keep
// ringing; Ctrl+Q (wired in Main) is the real quit.
Rectangle {
    id: bar
    property string title: "cobalt"
    property bool reloading: false
    signal reloadRequested()

    color: Theme.bg          // translucent — Hyprland blur shows through
    Rectangle {              // hairline under the bar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.divider
    }

    // whole-bar drag handle (buttons sit above it and eat their own clicks)
    MouseArea {
        anchors.fill: parent
        onPressed: Window.window.startSystemMove()
        onDoubleClicked: Window.window.visibility =
            Window.window.visibility === Window.Maximized ? Window.Windowed
                                                          : Window.Maximized
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 12
        spacing: 9

        Rectangle {          // accent dot — the app's little identity mark
            anchors.verticalCenter: parent.verticalCenter
            width: 9; height: 9; radius: 5
            color: Theme.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: bar.title
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            elide: Text.ElideRight
            width: Math.min(implicitWidth, bar.width - 160)
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 8
        spacing: 2

        component WinBtn: Rectangle {
            property alias glyph: label.text
            property color glyphColor: Theme.subtext
            property color hoverBg: Theme.glassSoft
            signal clicked()
            width: 34; height: 26; radius: Theme.radiusSm
            color: hover.containsMouse ? hoverBg : "transparent"
            Text {
                id: label
                anchors.centerIn: parent
                color: hover.containsMouse ? Theme.text : parent.glyphColor
                font.family: Theme.font
                font.pixelSize: 14
            }
            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: parent.clicked()
            }
        }

        WinBtn {
            glyph: bar.reloading ? "×" : "↻"   // ↻ / × while loading
            onClicked: bar.reloadRequested()
        }
        WinBtn {
            glyph: "–"   // – minimise
            onClicked: Window.window.showMinimized()
        }
        WinBtn {
            glyph: "✕"   // ✕ close (→ hide, per config)
            glyphColor: Theme.subtext
            hoverBg: Theme.warn
            onClicked: Window.window.close()
        }
    }
}
