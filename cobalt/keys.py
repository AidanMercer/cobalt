from PySide6.QtCore import Property, QEvent, QObject, Qt, QTimer, Signal, Slot

from . import commands

# The vim layer's entry point: every key in the app passes through KeyFilter
# (installed on the root window) before the focused item — the WebEngineView —
# ever sees it. Consuming = Teams never knows; passing = zero added latency.
# QML Keys handlers can't do this job: WebEngineView swallows keys without
# re-propagating, and moving focus off the view would break IME. Trimmed from
# beryl's KeyController to a single view: no tabs, marks, or passthrough.

DEFAULT_BINDS = {
    "normal": {
        "j": "scroll-down", "k": "scroll-up",
        "d": "scroll-half-down", "u": "scroll-half-up",
        "gg": "scroll-top", "G": "scroll-bottom",
        "r": "reload", "R": "reload-bypass",
        "f": "hint",
        "gi": "focus-input", "i": "mode-insert",
        "zi": "zoom-in", "zo": "zoom-out", "zz": "zoom-reset",
        ":": "cmdline-open :", "/": "cmdline-open /",
        "n": "search-next", "N": "search-prev",
        "gh": "home",
        # teams app bar — bare letters, no g prefix (h is the help sheet)
        "c": "chat", "e": "calendar", "a": "activity", "s": "calls",
        "h": "help",
        "<Esc>": "search-stop",
        "ZZ": "quit",
    },
    "insert": {
        "<Esc>": "mode-normal",
    },
}

_MODIFIER_KEYS = {
    Qt.Key.Key_Shift, Qt.Key.Key_Control, Qt.Key.Key_Alt, Qt.Key.Key_Meta,
    Qt.Key.Key_AltGr, Qt.Key.Key_CapsLock, Qt.Key.Key_NumLock,
    Qt.Key.Key_ScrollLock, Qt.Key.Key_Super_L, Qt.Key.Key_Super_R,
}

_SPECIAL = {
    Qt.Key.Key_Escape: "Esc", Qt.Key.Key_Return: "CR", Qt.Key.Key_Enter: "CR",
    Qt.Key.Key_Tab: "Tab", Qt.Key.Key_Backtab: "Tab",
    Qt.Key.Key_Backspace: "BS", Qt.Key.Key_Space: "Space",
    Qt.Key.Key_Up: "Up", Qt.Key.Key_Down: "Down",
    Qt.Key.Key_Left: "Left", Qt.Key.Key_Right: "Right",
    Qt.Key.Key_PageUp: "PgUp", Qt.Key.Key_PageDown: "PgDn",
    Qt.Key.Key_Home: "Home", Qt.Key.Key_End: "End",
    Qt.Key.Key_Insert: "Ins", Qt.Key.Key_Delete: "Del",
}


def keystr(ev):
    """One string vocabulary for keys, shared with the binds TOML: printables
    are themselves ("j", "G", ":"), everything else is angle notation
    ("<Esc>", "<C-d>"). None for bare modifiers, "DEAD" for dead keys."""
    key = ev.key()
    if key in _MODIFIER_KEYS:
        return None
    if Qt.Key.Key_Dead_Grave <= key <= Qt.Key.Key_Dead_Longsolidusoverlay:
        return "DEAD"

    mods = ev.modifiers()
    ctrl = bool(mods & Qt.KeyboardModifier.ControlModifier)
    alt = bool(mods & Qt.KeyboardModifier.AltModifier)
    meta = bool(mods & Qt.KeyboardModifier.MetaModifier)
    shift = bool(mods & Qt.KeyboardModifier.ShiftModifier)

    text = ev.text()
    if not ctrl and not alt and not meta and key != Qt.Key.Key_Space \
            and text and text.isprintable():
        return text   # shift is already baked into the char ("G", ":")

    name = _SPECIAL.get(key)
    if name is None:
        if Qt.Key.Key_F1 <= key <= Qt.Key.Key_F35:
            name = f"F{key - Qt.Key.Key_F1 + 1}"
        elif 0x20 <= key <= 0x7E:
            name = chr(key).lower()
        else:
            return None
    prefix = ("C-" if ctrl else "") + ("A-" if alt else "") + ("M-" if meta else "")
    if shift:
        prefix += "S-"
    if prefix or len(name) > 1:
        return f"<{prefix}{name}>"
    return name


class KeyController(QObject):
    """The modal state machine. Lives in Python so the binds come straight from
    config; QML only renders mode + pending."""
    modeChanged = Signal()
    pendingChanged = Signal()
    bindsChanged = Signal()

    def __init__(self, cfg, api, parent=None):
        super().__init__(parent)
        self._cfg = cfg
        self._api = api
        self._hints = None
        self._registry = {}
        self._mode = "normal"
        self._binds = {}
        self._count = ""
        self._seq = ""
        self._capture = None       # (command, count) waiting for one raw key
        self._pressed = {}         # key code → did we consume its press?
        self._mode_reason = "manual"

        self._seq_timer = QTimer(self)
        self._seq_timer.setSingleShot(True)
        self._seq_timer.timeout.connect(self._seq_timeout)

        self.reload_binds()

    def set_registry(self, registry):
        self._registry = registry
        self.bindsChanged.emit()

    def set_hints(self, hints):
        self._hints = hints

    def reload_binds(self):
        merged = {}
        user = self._cfg.get("binds", {})
        for mode, table in DEFAULT_BINDS.items():
            m = dict(table)
            over = user.get(mode)
            if isinstance(over, dict):
                for k, v in over.items():
                    if isinstance(v, str):
                        m[k] = v
            merged[mode] = {k: v for k, v in m.items() if v}
        self._binds = merged
        self.bindsChanged.emit()

    # ---- state shown in the status line -------------------------------------
    @Property(str, notify=modeChanged)
    def mode(self):
        return self._mode

    @Property(str, notify=pendingChanged)
    def pending(self):
        return self._count + self._seq

    @Property("QVariantList", notify=bindsChanged)
    def helpModel(self):
        """Rows for the h sheet: the live bind table joined to each command's
        own description, so rebinding in config.toml re-labels the sheet and a
        command with no desc/group never shows up half-documented."""
        rows = []
        for mode in ("normal", "insert"):
            for key, action in self._binds.get(mode, {}).items():
                cmd = self._registry.get(action.partition(" ")[0])
                if cmd is None or not cmd.group:
                    continue
                desc = commands.ACTION_DESC.get(action) or cmd.desc
                if not desc:
                    continue
                rows.append({"group": cmd.group, "key": key, "desc": desc})
        order = {g: i for i, g in enumerate(commands.GROUPS)}
        rows.sort(key=lambda r: (order.get(r["group"], 99), r["key"].lower()))
        return rows

    def set_mode(self, mode, reason="manual"):
        if mode == self._mode:
            return
        old = self._mode
        self._mode = mode
        self._mode_reason = reason
        self._reset_pending()
        self.modeChanged.emit()
        # leaving insert: blur Teams' editable so stray input (and IME
        # composition) has nowhere to land in normal mode
        if mode == "normal" and old == "insert":
            self._api.js("if(document.activeElement)document.activeElement.blur()")

    @Slot(bool)
    def pageEditable(self, on):
        """editable.js reports focus moving in/out of a text field. Auto-
        entered insert drops on blur; a manual `i` isn't cancelled by focus
        noise."""
        if on and self._mode == "normal":
            self.set_mode("insert", reason="page")
        elif not on and self._mode == "insert" and self._mode_reason == "page":
            self.set_mode("normal")

    @Slot()
    def cmdlineClosed(self):
        if self._mode == "command":
            self.set_mode("normal")

    @Slot(str)
    def setMode(self, mode):
        self.set_mode(mode)

    # ---- the filter feeds these ----------------------------------------------
    def press(self, ev):
        consumed = self._press(ev)
        self._pressed[ev.key()] = consumed
        return consumed

    def release(self, ev):
        return self._pressed.pop(ev.key(), False)

    def _press(self, ev):
        if self._mode == "command":
            return False          # the cmdline TextField owns its own keys
        if self._mode == "hint":
            ks = keystr(ev)
            if ks and ks != "DEAD" and self._hints is not None:
                self._hints.key(ks)
            return True           # hint mode owns every key
        if self._mode == "help":
            # the sheet is a glance, not a place to live: any real key dismisses
            # it (bare modifiers don't, so Shift alone doesn't flap it shut)
            if keystr(ev) is not None:
                self.set_mode("normal")
            return True
        if self._mode == "insert":
            ks = keystr(ev)
            cmdline = self._binds["insert"].get(ks) if ks else None
            if cmdline:
                self._dispatch(cmdline, 1)
                return True
            return False          # everything else reaches Teams natively

        # ---- normal mode ----
        ks = keystr(ev)
        if ks is None:
            return False
        if ks == "DEAD":
            return True

        if self._capture is not None:
            cmdline, count = self._capture
            self._capture = None
            self._update_pending()
            if len(ks) == 1:
                self._dispatch(f"{cmdline} {ks}", count)
            return True

        if ks.isdigit() and not self._seq and (self._count or ks != "0"):
            self._count += ks
            self._update_pending()
            return True

        binds = self._binds["normal"]
        seq = self._seq + ks
        is_prefix = any(k != seq and k.startswith(seq) for k in binds)
        if seq in binds and not is_prefix:
            self._fire(binds[seq])
            return True
        if seq in binds or is_prefix:
            self._seq = seq
            self._update_pending()
            self._seq_timer.start(int(self._cfg.get("seq_timeout_ms", 800)))
            return True

        had_pending = bool(self._seq)
        self._reset_pending()
        if had_pending:
            return self._press(ev)
        if len(ks) == 1:
            return True           # unbound printable — never leak typing into Teams
        return False              # unbound special/modifier combo — Teams' problem

    # ---- internals -----------------------------------------------------------
    def _fire(self, cmdline):
        try:
            count = max(1, min(int(self._count), 9999)) if self._count else 1
        except ValueError:
            count = 1
        self._reset_pending()
        self._dispatch(cmdline, count)

    def _dispatch(self, cmdline, count):
        name, _, arg = cmdline.partition(" ")
        cmd = self._registry.get(name)
        if cmd is None:
            self._api.toast.emit(f"unknown command: {name}", True)
            return
        if getattr(cmd, "takes_key", False) and not arg:
            self._capture = (name, count)
            self._update_pending()
            return
        cmd.fn(count=count, arg=arg)

    def _seq_timeout(self):
        seq = self._seq
        binds = self._binds["normal"]
        if seq and seq in binds:
            self._fire(binds[seq])
        else:
            self._reset_pending()

    def _reset_pending(self):
        self._seq_timer.stop()
        self._count = ""
        self._seq = ""
        self._capture = None
        self._update_pending()

    def _update_pending(self):
        self.pendingChanged.emit()


class KeyFilter(QObject):
    """Installed on the root QQuickWindow — sees every key event before the
    delivery agent hands it to the focused item (the WebEngineView)."""

    def __init__(self, controller, parent=None):
        super().__init__(parent)
        self._c = controller

    def eventFilter(self, obj, ev):
        t = ev.type()
        if t == QEvent.Type.KeyPress:
            return self._c.press(ev)
        if t == QEvent.Type.KeyRelease:
            return self._c.release(ev)
        return False
