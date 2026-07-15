import QtQuick
import QtQuick.Layouts
import QtWebEngine

// cobalt's single window: world80 glass titlebar + status line wrapping one
// persistent, vim-driven, transparent Teams view. Frameless; the titlebar
// moves it. The vim layer lives in Python (KeyController via a native event
// filter installed in main.py) — this file just renders and dispatches.
Window {
    id: win
    width: 1180
    height: 800
    minimumWidth: 480
    minimumHeight: 360
    visible: !Config.start_hidden
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "cobalt"

    // closing hides (calls keep ringing) unless the user really quits (Ctrl+Q)
    onClosing: function (close) {
        if (Config.close_to_background) {
            close.accepted = false
            win.hide()
        }
    }

    // regaining activation usually means the window/workspace just came back:
    // Chromium evicts occluded composited frames, so the view sits BLACK until
    // an event (a hover) wakes it. Blinking the view's visibility delivers
    // wasHidden/wasShown and forces a recomposite (beryl's fix). Deferred a
    // tick so the surface is re-exposed before the blink lands.
    onActiveChanged: if (active) Qt.callLater(repaintView)
    function repaintView() {
        view.visible = false
        view.visible = true
        if (!cmdline.active)
            view.forceActiveFocus()
    }

    Connections {
        target: App
        function onRaiseRequested() {
            win.show()
            win.raise()
            win.requestActivate()
        }
    }

    Shortcut { sequences: ["Ctrl+Q"]; onActivated: App.quit() }
    Shortcut { sequences: ["F5"]; onActivated: view.reload() }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TitleBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            // drop Teams' redundant "| Microsoft Teams" suffix
            title: (view.title || "").replace(/\s*\|\s*Microsoft Teams\s*$/i, "").trim() || "cobalt"
            reloading: view.loading
            onReloadRequested: view.loading ? view.stop() : view.reload()
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // theme-bg wash behind the transparent page so text stays legible
            // over bright wallpaper (beryl's page_scrim). Shows through the
            // stripped Teams content; 0 disables it. The WebView sits on top
            // and composites its transparent regions over this.
            Rectangle {
                anchors.fill: parent
                color: Theme.viewBg
                opacity: Config.transparent ? Config.page_scrim : 0
                visible: opacity > 0
            }

            WebView {
                id: view
                anchors.fill: parent
                focus: true
                Component.onCompleted: forceActiveFocus()
            }
        }

        StatusBar {
            id: footer
            Layout.fillWidth: true
            Layout.preferredHeight: 22
        }
    }

    // ex / search line — sits over the status bar while open
    CmdLine {
        id: cmdline
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 30
        onClosed: view.forceActiveFocus()
    }

    // transient toast for "no hints", "unknown command", etc.
    Rectangle {
        id: toast
        property string msg: ""
        visible: msg !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 34
        width: toastText.implicitWidth + 24
        height: 28
        radius: Theme.radiusSm
        color: Theme.card
        border.color: Theme.border
        border.width: 1
        Text {
            id: toastText
            anchors.centerIn: parent
            text: toast.msg
            color: toast.error ? Theme.warn : Theme.text
            font.pixelSize: 12
            font.family: Theme.font
        }
        property bool error: false
        Timer { id: toastTimer; interval: 2200; onTriggered: toast.msg = "" }
        function show(m, e) { error = e; msg = m; toastTimer.restart() }
    }

    // the h key sheet (covers the whole window while in help mode)
    HelpOverlay {
        anchors.fill: parent
    }

    // screen-share source chooser (covers the whole window when active)
    ScreenPicker {
        id: picker
        anchors.fill: parent
    }

    // ---- python → view dispatch ----------------------------------------------
    Connections {
        target: api

        function onJsRequested(script, world, rid) {
            if (rid > 0)
                view.runJavaScript(script, world, function (res) { api.jsDone(rid, res) })
            else
                view.runJavaScript(script, world)
        }
        function onZoomRequested(step) {
            view.zoomFactor = step === 0 ? 1.0
                : Math.max(0.3, Math.min(4.0, view.zoomFactor + step))
        }
        function onNavRequested(url) { view.url = url }
        function onReloadRequested(bypass) {
            bypass ? view.reloadAndBypassCache() : view.reload()
        }
        function onFindRequested(term, backwards) {
            if (backwards)
                view.findText(term, WebEngineView.FindBackward)
            else
                view.findText(term)
        }
        function onCmdlineOpenRequested(prefix, prefill) { cmdline.open(prefix, prefill) }
        function onFindCount(c) { footer.findCount = c }
        function onToast(t, e) { toast.show(t, e) }
    }

    // leaving command mode by any path closes the cmdline
    Connections {
        target: Vim
        function onModeChanged() {
            if (Vim.mode !== "command" && cmdline.active)
                cmdline.close()
        }
    }
}
