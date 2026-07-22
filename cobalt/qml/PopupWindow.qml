import QtQuick
import QtWebEngine

// window.open / target=_blank land here. Microsoft's login and "join meeting"
// flows open real popups, so these have to work or sign-in loops. Shares the
// one persistent profile, so cookies/session flow straight through.
Window {
    id: pop
    property var request: null

    width: 520; height: 640
    color: "transparent"
    flags: Qt.Window | Qt.Dialog | Qt.FramelessWindowHint
    visible: true

    Rectangle {
        anchors.fill: parent
        color: Theme.viewBg
        border.color: Theme.border
        border.width: 1

        Column {
            anchors.fill: parent
            Rectangle {          // slim drag/close bar
                width: parent.width; height: 32
                color: Theme.bg
                MouseArea {
                    anchors.fill: parent
                    onPressed: pop.startSystemMove()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.leftMargin: 12
                    text: view.title || "sign in"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                    elide: Text.ElideRight; width: parent.width - 60
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right; anchors.rightMargin: 6
                    width: 30; height: 24; radius: Theme.radiusSm
                    color: closeHover.containsMouse ? Theme.warn : "transparent"
                    Text {
                        anchors.centerIn: parent; text: "✕"
                        color: closeHover.containsMouse ? Theme.text : Theme.subtext
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    MouseArea {
                        id: closeHover; anchors.fill: parent
                        hoverEnabled: true; onClicked: pop.close()
                    }
                }
            }

            WebEngineView {
                id: view
                width: parent.width
                height: parent.height - 32
                profile: WebProfile
                backgroundColor: Theme.viewBg
                settings.screenCaptureEnabled: true

                Component.onCompleted: if (pop.request) pop.request.openIn(view)

                // same policy as the main view — Teams pops meetings out into
                // these windows, and an unhandled permission request is a
                // silent deny, which blocked the camera exactly where calls
                // actually happen
                onPermissionRequested: function (permission) {
                    var P = WebEnginePermission.PermissionType
                    var t = permission.permissionType
                    var isMedia = t === P.MediaAudioCapture || t === P.MediaVideoCapture
                                || t === P.MediaAudioVideoCapture
                                || t === P.DesktopAudioVideoCapture || t === P.DesktopVideoCapture
                    var benign = t === P.Notifications || t === P.ClipboardReadWrite
                    if (benign || (isMedia && Config.auto_grant_media))
                        permission.grant()
                    else
                        permission.deny()
                }

                // a popup that closes itself (auth complete) tears down the window
                onWindowCloseRequested: pop.close()
                onNewWindowRequested: function (r) { r.openIn(view) }

                // popped-out meetings attach files too
                UploadPicker { view: view }
            }
        }
    }

    onClosing: destroy()
}
