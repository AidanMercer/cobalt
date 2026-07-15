from PySide6.QtGui import QGuiApplication

# Small command registry for cobalt's vim layer. Each bind's action string
# (e.g. "scroll-down", "cmdline-open :") resolves here. Scroll/focus commands
# drive the isolated-world helpers in js/nav.js + js/hints.js (world 1), which
# find the right scroll container inside Teams (window scroll does nothing —
# Teams scrolls inner overflow panes).


class Command:
    def __init__(self, fn, takes_key=False, desc="", group=""):
        self.fn = fn
        self.takes_key = takes_key
        self.desc = desc      # one-liner for the h help overlay
        self.group = group    # which help column it lands in


# help overlay column order; anything ungrouped is dropped from the sheet
GROUPS = ["motion", "teams", "page", "search", "modes"]


def build(api, keys, hints, cfg):
    step = int(cfg.get("scroll_step", 80))

    def js1(script):
        api.js(script, world=1)

    reg = {}

    def cmd(name, fn, takes_key=False, desc="", group=""):
        reg[name] = Command(fn, takes_key, desc, group)

    # --- scroll / motion (all target the active scroll pane, iframes included)
    cmd("scroll-down",      lambda count, arg: js1(f"__cobalt.scroll({step * count})"),
        desc="scroll down", group="motion")
    cmd("scroll-up",        lambda count, arg: js1(f"__cobalt.scroll({-step * count})"),
        desc="scroll up", group="motion")
    cmd("scroll-half-down", lambda count, arg: js1(f"__cobalt.scrollHalf({count})"),
        desc="half page down", group="motion")
    cmd("scroll-half-up",   lambda count, arg: js1(f"__cobalt.scrollHalf({-count})"),
        desc="half page up", group="motion")
    cmd("scroll-top",       lambda count, arg: js1("__cobalt.scrollEnd(-1)"),
        desc="top", group="motion")
    cmd("scroll-bottom",    lambda count, arg: js1("__cobalt.scrollEnd(1)"),
        desc="bottom", group="motion")

    # --- links / input
    cmd("hint",         lambda count, arg: hints.start(),
        desc="hint links", group="motion")
    cmd("focus-input",  lambda count, arg: js1("__cobalt.firstInput()"),
        desc="focus the composer", group="motion")
    cmd("mode-insert",  lambda count, arg: keys.set_mode("insert"),
        desc="insert mode", group="modes")
    cmd("mode-normal",  lambda count, arg: keys.set_mode("normal"),
        desc="back to normal mode", group="modes")

    # --- teams app bar: click the rail button, the same thing Teams' own
    # Ctrl+Shift+N shortcuts do, so no SPA reload and no lost scroll position.
    def rail(name, label):
        def go(count, arg):
            def done(ok):
                if not ok:
                    api.toast.emit(f"no {label} in the app bar", True)
            api.js(f"__cobalt.rail('{name}')", cb=done, world=1)
        return go

    cmd("chat",     rail("chat", "Chat"),         desc="Chat", group="teams")
    cmd("calendar", rail("calendar", "Calendar"), desc="Calendar", group="teams")
    cmd("activity", rail("activity", "Activity"), desc="Activity feed", group="teams")
    cmd("calls",    rail("calls", "Calls"),       desc="Calls", group="teams")

    # --- page
    cmd("reload",        lambda count, arg: api.reloadRequested.emit(False),
        desc="reload", group="page")
    cmd("reload-bypass", lambda count, arg: api.reloadRequested.emit(True),
        desc="hard reload", group="page")
    cmd("home",          lambda count, arg: api.navRequested.emit(cfg.get("url", "")),
        desc="home", group="page")
    cmd("zoom-in",       lambda count, arg: api.zoomRequested.emit(0.1),
        desc="zoom in", group="page")
    cmd("zoom-out",      lambda count, arg: api.zoomRequested.emit(-0.1),
        desc="zoom out", group="page")
    cmd("zoom-reset",    lambda count, arg: api.zoomRequested.emit(0.0),
        desc="reset zoom", group="page")

    # --- search
    cmd("search-next",  lambda count, arg: api.find_again(False),
        desc="next match", group="search")
    cmd("search-prev",  lambda count, arg: api.find_again(True),
        desc="previous match", group="search")
    cmd("search-stop",  lambda count, arg: api.find(""),
        desc="clear search", group="search")

    # --- cmdline (arg carries the prefix: "cmdline-open :" / "cmdline-open /")
    def open_cmdline(count, arg):
        keys.set_mode("command")
        api.cmdlineOpenRequested.emit(arg or ":", "")
    cmd("cmdline-open", open_cmdline, group="modes")

    cmd("help", lambda count, arg: keys.set_mode("help"),
        desc="this list", group="modes")   # the sheet's header says how to close it

    cmd("quit", lambda count, arg: QGuiApplication.quit(), desc="quit", group="page")

    return reg


# a bind's full action string (arg included) → help text, for the few commands
# whose own desc reads too generically on the sheet ("cmdline-open" is ':' or
# '/' depending on the arg the bind passes).
ACTION_DESC = {
    "cmdline-open :": "command line",
    "cmdline-open /": "search the page",
}


# ex-line names → registry command names. Keeps ":q" / ":reload" working off
# the same handlers the binds use.
_EX_ALIASES = {
    "q": "quit", "quit": "quit",
    "r": "reload", "reload": "reload",
    "home": "home",
    "zi": "zoom-in", "zo": "zoom-out", "zz": "zoom-reset",
    "h": "help", "help": "help",
    "chat": "chat", "calendar": "calendar",
    "activity": "activity", "calls": "calls",
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
