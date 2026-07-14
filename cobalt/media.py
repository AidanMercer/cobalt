from PySide6.QtCore import Property, QObject, Signal, Slot


def _model(obj, name):
    """screensModel/windowsModel may surface as a property or a getter
    depending on the PySide6 build — accept either."""
    attr = getattr(obj, name)
    return attr() if callable(attr) else attr


class MediaController(QObject):
    """Bridges QtWebEngine's desktopMediaRequested into the QML picker.

    The request carries two QAbstractListModels (screens, windows) and wants a
    QModelIndex back through selectScreen()/selectWindow(). Building that index
    HERE — where model.index() is unconditionally callable — keeps the QML
    declarative and sidesteps the question of whether QML can construct a
    QModelIndex itself. QML just shows the models and hands back a row number.
    """
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._req = None
        self._screens = None
        self._windows = None

    @Property(bool, notify=changed)
    def active(self):
        return self._req is not None

    @Property(QObject, notify=changed)
    def screens(self):
        return self._screens

    @Property(QObject, notify=changed)
    def windows(self):
        return self._windows

    @Slot(object)
    def present(self, request):
        """Called from QML's onDesktopMediaRequested. Not resolving the request
        hangs the share, so cancel()/selectX() must always follow."""
        self._req = request
        self._screens = _model(request, "screensModel") if request is not None else None
        self._windows = _model(request, "windowsModel") if request is not None else None
        self.changed.emit()

    @Slot(int)
    def selectScreen(self, row):
        if self._req is not None and self._screens is not None:
            self._req.selectScreen(self._screens.index(row, 0))
        self._clear()

    @Slot(int)
    def selectWindow(self, row):
        if self._req is not None and self._windows is not None:
            self._req.selectWindow(self._windows.index(row, 0))
        self._clear()

    @Slot()
    def cancel(self):
        if self._req is not None:
            self._req.cancelRequest()
        self._clear()

    def _clear(self):
        self._req = None
        self._screens = None
        self._windows = None
        self.changed.emit()
