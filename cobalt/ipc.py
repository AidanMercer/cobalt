import hashlib
import os

from PySide6.QtCore import QObject, Signal
from PySide6.QtNetwork import QLocalServer, QLocalSocket

from . import config

# One cobalt per profile: a Chromium profile dir can't be shared between
# processes, so a second launch just pokes the first over this socket (raise +
# focus the window) and exits. Scoped to the data dir so a sandboxed cobalt
# (custom XDG dirs) doesn't poke the real one.
_SOCKET = (f"cobalt-{os.getuid()}-"
           + hashlib.sha1(str(config.DATA_HOME).encode()).hexdigest()[:8])


def try_forward():
    """If another instance is listening, ask it to surface its window and
    return True (the caller should exit). False means we're first — go ahead
    and own the profile."""
    sock = QLocalSocket()
    sock.connectToServer(_SOCKET)
    if not sock.waitForConnected(300):
        return False
    sock.write(b"raise\n")
    sock.flush()
    sock.waitForBytesWritten(500)
    sock.disconnectFromServer()
    return True


class InstanceServer(QObject):
    """The first instance's end of the socket. Emits raiseRequested for every
    later launch that got forwarded here."""
    raiseRequested = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._server = QLocalServer(self)
        self._server.newConnection.connect(self._accept)
        # deliberately NO removeServer here: unlinking first would let a
        # startup-race loser destroy the winner's socket. On failure the caller
        # re-tries forwarding, and only then force_listen() clears what must be
        # a crash-stale socket.
        self.ok = self._server.listen(_SOCKET)

    def force_listen(self):
        """Nobody answered the socket, so it's a stale leftover: clear it."""
        QLocalServer.removeServer(_SOCKET)
        self.ok = self._server.listen(_SOCKET)
        if not self.ok:
            print(f"[ipc] listen failed: {self._server.errorString()}", flush=True)

    def _accept(self):
        sock = self._server.nextPendingConnection()
        if sock is None:
            return
        sock.readyRead.connect(lambda: self._read(sock))
        sock.disconnected.connect(sock.deleteLater)

    def _read(self, sock):
        while sock.canReadLine():
            sock.readLine()   # payload is always "raise"; content doesn't matter
            self.raiseRequested.emit()
