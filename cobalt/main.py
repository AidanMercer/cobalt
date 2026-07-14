import os
import sys
import time
from pathlib import Path

from PySide6.QtCore import (Property, QFileSystemWatcher, QObject, Qt, QTimer,
                            QUrl, Signal, Slot, qInstallMessageHandler)
from PySide6.QtGui import QFont, QGuiApplication, QSurfaceFormat
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWebEngineQuick import QtWebEngineQuick

from . import commands, config, ipc, webprofile
from .api import Api
from .hints import Hints
from .keys import KeyController, KeyFilter
from .media import MediaController
from .theme import ThemeManager

_LOG_CAP = 1024 * 1024


class _Tee:
    """Fan writes to several streams so everything lands in the log even when
    the launcher sends stdout to /dev/null."""
    def __init__(self, *streams):
        self._streams = [s for s in streams if s is not None]

    def write(self, s):
        for st in self._streams:
            try:
                st.write(s)
                st.flush()
            except Exception:
                pass

    def flush(self):
        for st in self._streams:
            try:
                st.flush()
            except Exception:
                pass


def _start_logging():
    try:
        config.CACHE_HOME.mkdir(parents=True, exist_ok=True)
        mode = "w" if (config.LOG_FILE.exists()
                       and config.LOG_FILE.stat().st_size > _LOG_CAP) else "a"
        logf = open(config.LOG_FILE, mode, buffering=1)
    except Exception:
        return
    sys.stdout = _Tee(sys.__stdout__, logf)
    sys.stderr = _Tee(sys.__stderr__, logf)
    print(f"\n==== cobalt session {time.strftime('%Y-%m-%d %H:%M:%S')} ====", flush=True)


def _qt_message_handler(mode, ctx, msg):
    # page JS console output arrives here too (ctx.file = the page's script
    # url) — that's Teams' own noise, not ours; keep it out of the log
    if ctx.file and ctx.file.startswith(("http:", "https:")):
        return
    loc = f" ({ctx.file}:{ctx.line})" if ctx.file else ""
    print(f"[qml] {msg}{loc}", file=sys.stderr, flush=True)


class App(QObject):
    """The seam between Python and QML. Carries the raise-on-second-launch
    signal, the reskin (config live-reload) signal, the quit action, and the
    (optional) user stylesheet."""
    raiseRequested = Signal()
    reskinRequested = Signal()

    def __init__(self, cfg, parent=None):
        super().__init__(parent)
        self._css = ""
        path = (cfg.get("custom_css") or "").strip()
        if path:
            try:
                self._css = Path(path).expanduser().read_text()
            except OSError as e:
                print(f"[css] could not read {path}: {e}", flush=True)

    @Property(str, constant=True)
    def customCss(self):
        return self._css

    @Slot()
    def quit(self):
        QGuiApplication.quit()


def main():
    t0 = time.monotonic()
    _start_logging()

    config.ensure()
    cfg = config.load()

    # force_dark asks Chromium to auto-darken *all* web content — the only way
    # to darken the Teams canvas itself, since Teams renders in iframes CSS
    # can't reach. Auto-inverted, so rougher than Teams' own dark theme (which
    # is the better fix); off by default. Must be set before initialize().
    if cfg.get("force_dark"):
        flags = os.environ.get("QTWEBENGINE_CHROMIUM_FLAGS", "")
        flags += " --blink-settings=forceDarkModeEnabled=true,forceDarkModeImagePolicy=2"
        os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = flags.strip()

    # translucent chrome so Hyprland blurs behind it, plus the WebEngine init —
    # both must happen before the QGuiApplication exists (the WebEngine one is a
    # hard Chromium requirement, not a nicety).
    fmt = QSurfaceFormat()
    fmt.setAlphaBufferSize(8)
    QSurfaceFormat.setDefaultFormat(fmt)
    qInstallMessageHandler(_qt_message_handler)
    QtWebEngineQuick.initialize()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("cobalt")
    app.setDesktopFileName("cobalt")   # Wayland app_id Hyprland matches

    # single instance: a Chromium profile can't be shared, so a second launch
    # just raises the running window and exits before touching the profile.
    if ipc.try_forward():
        print("[ipc] already running — raised it", flush=True)
        return
    server = ipc.InstanceServer(app)
    if not server.ok:
        if ipc.try_forward():
            print("[ipc] lost the startup race — raised the winner", flush=True)
            return
        server.force_listen()   # nobody home: crash-stale socket

    theme = ThemeManager(app)
    profile = webprofile.build(cfg, app)
    bridge = App(cfg, app)
    media = MediaController(app)

    # vim layer: the KeyController is a modal state machine driven by KeyFilter
    # (a native event filter installed on the window below), dispatching to the
    # command registry; the isolated-world JS helpers run through Api.
    api = Api(app)
    keys = KeyController(cfg, api, app)
    hints = Hints(cfg, api, app)
    keys.set_hints(hints)
    hints.set_keys(keys)
    registry = commands.build(api, keys, hints, cfg)
    keys.set_registry(registry)
    api.set_ex_handler(lambda line: commands.run_ex(line, registry, api))
    key_filter = KeyFilter(keys, app)

    def apply_font():
        app.setFont(QFont(theme.theme_dict()["font"]))
    apply_font()

    # tell web content (login pages, and Teams if set to "follow system") to
    # render dark/light to match the rice — this is what makes prefers-color-
    # scheme report dark. Teams' own theme setting still wins for its main UI,
    # so pair this with Teams → Settings → Appearance → Dark for the best look.
    def apply_color_scheme():
        try:
            app.styleHints().setColorScheme(
                Qt.ColorScheme.Dark if theme.is_dark() else Qt.ColorScheme.Light)
        except AttributeError:
            pass   # setColorScheme is Qt 6.8+; older Qt just skips this
    apply_color_scheme()

    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    ctx.setContextProperty("Theme", theme.theme_dict())
    ctx.setContextProperty("Rice", theme)
    ctx.setContextProperty("Config", cfg)
    ctx.setContextProperty("WebProfile", profile)
    ctx.setContextProperty("App", bridge)
    ctx.setContextProperty("Media", media)
    ctx.setContextProperty("Vim", keys)   # "Keys" would collide with QML's attached Keys
    ctx.setContextProperty("api", api)

    # re-set the Theme dict on every rice switch; QML re-evaluates every Theme.*
    # binding. cobalt only themes its own chrome (Teams renders in iframes we
    # don't touch), so there's none of beryl's page-CSS ordering to defer here.
    def retheme():
        ctx.setContextProperty("Theme", theme.theme_dict())
        apply_font()
        apply_color_scheme()
    theme.themeChanged.connect(retheme)

    server.raiseRequested.connect(bridge.raiseRequested)

    engine.load(QUrl.fromLocalFile(str(Path(__file__).parent / "qml" / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)

    win = engine.rootObjects()[0]
    # the vim layer's entry point: every key hits this filter before the
    # focused WebEngineView, which otherwise swallows them
    win.installEventFilter(key_filter)

    # live config reload — so the look knobs (page_scrim, page_colors,
    # transparent) can be dialled in without a restart. Watch the file and its
    # dir (editors replace it); cfg is mutated in place so bindings see fresh
    # values, then Config is re-set and the page re-skins.
    watcher = QFileSystemWatcher(app)
    debounce = QTimer(app)
    debounce.setSingleShot(True)
    debounce.setInterval(250)

    def reload_config():
        fresh = config.load()
        cfg.clear()
        cfg.update(fresh)
        keys.reload_binds()
        ctx.setContextProperty("Config", cfg)
        bridge.reskinRequested.emit()
        if config.CONFIG_FILE.exists() and str(config.CONFIG_FILE) not in watcher.files():
            watcher.addPath(str(config.CONFIG_FILE))

    debounce.timeout.connect(reload_config)
    watcher.fileChanged.connect(lambda _p: debounce.start())
    watcher.directoryChanged.connect(lambda _p: debounce.start())
    watcher.addPath(str(config.CONFIG_DIR))
    if config.CONFIG_FILE.exists():
        watcher.addPath(str(config.CONFIG_FILE))
    win.frameSwapped.connect(
        lambda: print(f"[startup] first frame in {time.monotonic() - t0:.3f}s", flush=True),
        Qt.ConnectionType.SingleShotConnection)

    sys.exit(app.exec())
