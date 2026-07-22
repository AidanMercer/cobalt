import QtQuick
import QtWebEngine

// Drop inside a WebEngineView to make mica its upload picker:
//     UploadPicker { view: view }
//
// Left unclaimed, QtWebEngine draws its own bare QtQuick FileDialog (Qt's
// native path can't save us — qt6ct exposes no file-dialog helper, so the
// xdg-portal → mica chain is never asked). Claiming the signal here routes
// every <input type=file> through `mica --pick` instead. Both the main view
// and popped-out meeting windows need one.
Item {
    id: hook
    required property var view
    property var pending: null   // { id, request } — parking the JS-owned
                                 // request here is what keeps it alive while
                                 // mica is up; dropping it lets it go

    Connections {
        target: hook.view
        function onFileDialogRequested(request) {
            var mode = "file"
            if (request.mode === FileDialogRequest.FileModeOpenMultiple)
                mode = "files"
            else if (request.mode === FileDialogRequest.FileModeUploadFolder)
                mode = "dir"
            else if (request.mode === FileDialogRequest.FileModeSave)
                mode = "save"
            var id = Picker.pick(mode, request.defaultFileName)
            if (id < 0) {               // no picker to open — don't leave the page hanging
                request.dialogReject()
                return
            }
            request.accepted = true     // ours now; Chromium keeps its dialog shut
            hook.pending = { id: id, request: request }
        }
    }

    Connections {
        target: Picker
        function onPicked(id, files) {
            var p = hook.pending
            if (!p || p.id !== id)
                return                  // another view's picker
            hook.pending = null
            if (files.length > 0)
                p.request.dialogAccept(files)
            else
                p.request.dialogReject()   // cancelled
        }
    }
}
