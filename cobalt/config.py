import os
import tomllib
from pathlib import Path

# `or` not a get() default: an empty (set-but-blank) XDG var must not yield
# relative paths in whatever directory cobalt was launched from
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "cobalt"
LOG_FILE = CACHE_HOME / "cobalt.log"

DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "cobalt"

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "cobalt"
CONFIG_FILE = CONFIG_DIR / "config.toml"

_DEFAULTS = {
    # the Teams web app. v2 is the current work/school client; teams.live.com
    # is personal. Point this wherever your tenant lives.
    "url": "https://teams.microsoft.com/v2/",

    # UA sent to Teams. Empty => a plain Chrome-on-Linux string built from the
    # real engine version (see webprofile). Teams sniffs the UA and degrades a
    # stock QtWebEngine string to "unsupported browser", so we never send that.
    # Set an Edge UA here if a feature insists on Edge.
    "user_agent": "",

    # camera / mic / notifications / clipboard are auto-granted to the Teams
    # origin so a call doesn't stop to ask every time. Screen SHARE is never
    # auto-granted — it always goes through the picker. Set false to be prompted.
    "auto_grant_media": True,

    # closing the window hides it (calls keep ringing, notifications keep
    # arriving) instead of quitting. Re-launch cobalt — or bind a key — to
    # raise it again. Ctrl+Q always quits for real.
    "close_to_background": True,

    # start hidden in the background (for autostart): the app is live and can
    # ring/notify, but no window shows until you raise it.
    "start_hidden": False,

    # ask Chromium to auto-darken ALL web content, including the Teams iframes
    # that CSS can't reach. It's an automatic invert, so it looks rougher than
    # Teams' own dark theme — prefer Teams → Settings → Appearance → Dark, and
    # only reach for this if you'd rather not touch Teams' settings.
    "force_dark": False,

    # a stylesheet injected into the top frame. Best-effort — Teams v2 renders
    # most content inside iframes that this can't reach, so treat it as accent
    # polish, not a reskin. Path is expanded (~ ok).
    "custom_css": "",

    # where Teams attachments land.
    "download_dir": "~/Downloads",

    # "full send" transparency: strip Teams' backgrounds so the wallpaper +
    # Hyprland blur show through, and repaint its text/links in the rice
    # palette. Injected into every frame (reaches Teams' iframes). Fragile by
    # nature — Teams' DOM churns — so it's a toggle.
    "transparent": True,
    # palette forced onto the transparent page: "auto" follows the rice,
    # "dark"/"light" pin it.
    "page_colors": "auto",
    # a wash of the theme background BEHIND the transparent page (0 = bare
    # wallpaper, 1 = opaque). Without it, text sits on the raw wallpaper and
    # washes out over bright regions — same knob beryl uses for legibility.
    "page_scrim": 0.35,

    # --- vim nav ---
    "scroll_step": 80,          # px per j/k (times the count)
    "hint_chars": "asdfghjkl",  # link-hint label alphabet (home row)
    "seq_timeout_ms": 800,      # how long a pending multi-key sequence waits

    # third-party cookies are blocked EXCEPT cookies belonging to these
    # domains — microsoft SSO silently refreshes tokens through
    # login.microsoftonline.com iframes and Teams breaks without them.
    "cookie_allow_3p": [
        "login.microsoftonline.com", "login.live.com",
        "login.windows.net", "login.microsoft.com",
        "microsoftonline.com", "office.com", "office365.com",
    ],
}

# written to ~/.config/cobalt/config.toml on first run so the knobs are
# discoverable.
_TEMPLATE = """\
# cobalt config — every line is optional; delete one to use its default.

url = "https://teams.microsoft.com/v2/"   # teams.live.com for personal accounts
user_agent = ""            # blank = plain Chrome UA; set an Edge UA if a feature demands it

auto_grant_media = true    # auto-allow cam/mic/notifications (screen SHARE still uses the picker)
close_to_background = true # closing hides the window; calls keep ringing. Ctrl+Q really quits.
start_hidden = false       # start in the background with no window (for autostart)
force_dark = false         # auto-darken ALL web content (rougher than Teams' own dark theme)

transparent = true         # strip Teams' backgrounds so wallpaper+blur show through, recolor to the rice
page_colors = "auto"       # transparent-page palette: auto (follow rice) / dark / light
page_scrim = 0.35          # theme-bg wash behind the page (0 bare wallpaper .. 1 opaque) — legibility

scroll_step = 80           # px per j/k, times the count
hint_chars = "asdfghjkl"   # f-hint label alphabet (home row)
seq_timeout_ms = 800       # multi-key sequences (gg) give up after this

custom_css = ""            # a stylesheet injected into the top frame (best-effort; Teams uses iframes)
download_dir = "~/Downloads"

# third-party cookies are blocked except cookies belonging to these domains
# (microsoft SSO refreshes tokens through login.microsoftonline.com iframes).
cookie_allow_3p = [
  "login.microsoftonline.com", "login.live.com",
  "login.windows.net", "login.microsoft.com",
  "microsoftonline.com", "office.com", "office365.com",
]
"""


def ensure():
    """Drop a commented default config on first run. Best-effort — never blocks
    startup."""
    try:
        if not CONFIG_FILE.exists():
            CONFIG_DIR.mkdir(parents=True, exist_ok=True)
            CONFIG_FILE.write_text(_TEMPLATE)
    except OSError:
        pass


def load():
    cfg = {k: (v.copy() if isinstance(v, (dict, list)) else v)
           for k, v in _DEFAULTS.items()}
    try:
        data = tomllib.loads(CONFIG_FILE.read_text())
    except (OSError, tomllib.TOMLDecodeError):
        return cfg
    for key in _DEFAULTS:
        if key in data:
            cfg[key] = data[key]
    return cfg
