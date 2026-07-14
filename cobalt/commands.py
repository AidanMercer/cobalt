from PySide6.QtGui import QGuiApplication

# Small command registry for cobalt's vim layer. Each bind's action string
# (e.g. "scroll-down", "cmdline-open :") resolves here. Scroll/focus commands
# drive the isolated-world helpers in js/nav.js + js/hints.js (world 1), which
# find the right scroll container inside Teams (window scroll does nothing —
# Teams scrolls inner overflow panes).


class Command:
    def __init__(self, fn, takes_key=False):
        self.fn = fn
        self.takes_key = takes_key


def build(api, keys, hints, cfg):
    step = int(cfg.get("scroll_step", 80))

    def js1(script):
        api.js(script, world=1)

    reg = {}

    def cmd(name, fn, takes_key=False):
        reg[name] = Command(fn, takes_key)

    # --- scroll / motion (all target the active scroll pane, iframes included)
    cmd("scroll-down",      lambda count, arg: js1(f"__cobalt.scroll({step * count})"))
    cmd("scroll-up",        lambda count, arg: js1(f"__cobalt.scroll({-step * count})"))
    cmd("scroll-half-down", lambda count, arg: js1(f"__cobalt.scrollHalf({count})"))
    cmd("scroll-half-up",   lambda count, arg: js1(f"__cobalt.scrollHalf({-count})"))
    cmd("scroll-top",       lambda count, arg: js1("__cobalt.scrollEnd(-1)"))
    cmd("scroll-bottom",    lambda count, arg: js1("__cobalt.scrollEnd(1)"))

    # --- links / input
    cmd("hint",         lambda count, arg: hints.start())
    cmd("focus-input",  lambda count, arg: js1("__cobalt.firstInput()"))
    cmd("mode-insert",  lambda count, arg: keys.set_mode("insert"))

    # --- page
    cmd("reload",        lambda count, arg: api.reloadRequested.emit(False))
    cmd("reload-bypass", lambda count, arg: api.reloadRequested.emit(True))
    cmd("home",          lambda count, arg: api.navRequested.emit(cfg.get("url", "")))
    cmd("zoom-in",       lambda count, arg: api.zoomRequested.emit(0.1))
    cmd("zoom-out",      lambda count, arg: api.zoomRequested.emit(-0.1))
    cmd("zoom-reset",    lambda count, arg: api.zoomRequested.emit(0.0))

    # --- search
    cmd("search-next",  lambda count, arg: api.find_again(False))
    cmd("search-prev",  lambda count, arg: api.find_again(True))
    cmd("search-stop",  lambda count, arg: api.find(""))

    # --- cmdline (arg carries the prefix: "cmdline-open :" / "cmdline-open /")
    def open_cmdline(count, arg):
        keys.set_mode("command")
        api.cmdlineOpenRequested.emit(arg or ":", "")
    cmd("cmdline-open", open_cmdline)

    cmd("quit", lambda count, arg: QGuiApplication.quit())

    return reg


# ex-line names → registry command names. Keeps ":q" / ":reload" working off
# the same handlers the binds use.
_EX_ALIASES = {
    "q": "quit", "quit": "quit",
    "r": "reload", "reload": "reload",
    "home": "home",
    "zi": "zoom-in", "zo": "zoom-out", "zz": "zoom-reset",
}


def run_ex(line, registry, api):
    line = (line or "").strip()
    if not line:
        return
    name = line.split()[0]
    target = _EX_ALIASES.get(name)
    cmd = registry.get(target) if target else None
    if cmd is None:
        api.toast.emit(f"unknown: :{name}", True)
        return
    cmd.fn(count=1, arg="")
