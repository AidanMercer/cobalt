# cobalt

A lightweight, world80-native **Microsoft Teams** client — the full web app
(chat, calls, meetings, screen share) wrapped in your own frameless glass
chrome instead of Electron.

It's a single-site fork of [beryl](../beryl): one persistent QtWebEngine view
pointed at `teams.microsoft.com`, with beryl's rice-theming, single-instance,
and profile machinery reused. Because it rides the `qt6-webengine` you already
have installed, it ships **no second Chromium** — that's the whole "lightweight"
pitch versus an Electron wrapper.

## Why a wrapper at all?

Teams meetings are WebRTC + proprietary H.264 signalling that only Microsoft's
web stack speaks — there is no browser-engine-free path to calls. So cobalt
doesn't reimplement Teams; it gives the web app a native, themeable frame and
handles the desktop bits a bare browser tab can't: a screen-share source picker,
auto-granted mic/cam, desktop notifications, and background-survival so calls
keep ringing when the window is closed.

## Status

**Unproven — not yet run.** The one thing to verify before trusting it is
*sending your screen* into a call: that path (`desktopMediaRequested` → the
picker → Wayland portal/PipeWire) is the newest part of QtWebEngine. Everything
else (receiving video, camera, mic, chat, auth) is well-trodden. If screen-send
works on your machine, cobalt is good; if it never captures, the fallback is a
slim Electron shell (see `~/.claude/plans/cobalt.md`).

## Install

```sh
sudo pacman -S qt6-webengine libnotify        # qt6-webengine must have H.264 (Arch's does)
pip install --user 'PySide6>=6.8'             # or use the distro package
cp cobalt.desktop ~/.local/share/applications/
```

Bind a key in Hyprland (raises if already running):

```
bind = SUPER, T, exec, /home/aidan/dev/cobalt/cobalt.sh
```

Floating + sized, so it behaves like a chat app rather than a tile:

```
windowrulev2 = float, class:^(cobalt)$
windowrulev2 = size 1180 800, class:^(cobalt)$
windowrulev2 = center, class:^(cobalt)$
```

## Run

```sh
./cobalt.sh
```

First launch opens Microsoft's real login (in a popup window — that's expected;
auth uses `window.open`). The session persists, so you sign in once.

## Vim navigation

cobalt is vim-driven like beryl — a native key filter intercepts keys before
the Teams view (which otherwise swallows them). Normal mode by default.

| Key | Action |
|-----|--------|
| `h` | the key sheet — every bind, grouped; any key closes it |
| `c` / `e` | jump to Chat / Calendar · `a` Activity, `s` Calls |
| `f` | link hints — every clickable Teams control gets a home-row label; type it to click (reaches into same-origin iframes) |
| `j` / `k` | scroll the pane under the cursor down / up (Teams scrolls inner panes, not the window) |
| `d` / `u` | half-page down / up · `gg` / `G` top / bottom |
| `i` / `Esc` | insert mode (type into Teams) / back to normal · `gi` focus first input |
| `:` | ex line — `:q` quit, `:reload`, `:home`, `:zi`/`:zo`/`:zz` zoom, `:chat`/`:calendar` |
| `/` then `n` / `N` | find in page, next / prev |
| `zi` / `zo` / `zz` | zoom in / out / reset |
| `r` / `R` | reload / reload bypassing cache |
| `ZZ` or `Ctrl+Q` | quit for real (closing the window only hides it) |

The rail jumps (`c`/`e`/`a`/`s`) click Teams' own app-bar buttons, so they cost
no reload. They're normal-mode binds — Teams focuses the composer on load, which
auto-enters insert mode, so it's `Esc` first.

Counts work (`5j`). Binds are overridable under `[binds.normal]` in the config;
the `h` sheet reads the live bind table, so a rebind re-labels itself.
The status line shows the current mode and pending keys.

Other:

| Key | Action |
|-----|--------|
| `F5` | reload |
| drag titlebar | move · double-click titlebar | maximise |

## Config

`~/.config/cobalt/config.toml` is written on first run, fully commented. Knobs:
`url` (work vs `teams.live.com`), `user_agent` (blank = Chrome; set Edge if a
feature demands it), `transparent`, `page_colors` (auto/dark/light),
**`page_scrim`** (theme-bg wash behind the page — raise toward 0.5 if text
washes out over a bright wallpaper, lower toward 0.2 for more see-through),
`force_dark`, `auto_grant_media`, `close_to_background`, `start_hidden`,
`custom_css`, `download_dir`, `cookie_allow_3p` (the Microsoft SSO allow-list —
don't remove it or login loops). Page text is the rice theme's **accent**
colour (legibility-clamped), so it follows every theme switch.

If Teams can't see your camera/mic, launch with `cobalt.sh --allow-devices`
(alias `--allow-media`) — it forces `auto_grant_media` on for that run,
whatever the config says. Note cobalt is single-instance: if it's already
running, quit it (`Ctrl+Q`) first or the flag is ignored.

## Theming — "full send" transparency

`transparent = true` (default) strips Teams' backgrounds so your wallpaper +
Hyprland blur show through, and repaints its text/links in the rice palette.
The engine is lifted from beryl (built for Azure's iframe-heavy portal, which is
exactly Teams' shape): it injects into **every frame** (`runsOnSubFrames`) and
reaches into same-origin iframes from the parent, plus shadow DOM, CSP-strict
`adoptedStyleSheets`, and a MutationObserver to re-strip Teams' constant DOM
churn. This is what themes Teams' actual content where an Electron `insertCss`
can't.

It is **fragile by nature** — Teams reshapes its DOM and will occasionally punch
opaque holes or mis-tint something; that's the cost of "full send," and it's a
re-tune, not a rebuild. Turn it off (`transparent = false`) for stock Teams in a
themed frame, or set `force_dark = true` for a stable auto-dark instead. The
chrome (titlebar, status line, picker, popups) is always fully riced regardless.

cobalt follows the live rice exactly like the rest of world80 (`theme.py` lifted
from beryl — awww resolve + `config.toml` tokens); a wallpaper/theme switch
re-skins both the chrome and the injected page styles live.

## Layout

```
cobalt/
  main.py          window + wiring + the App↔QML bridge + KeyFilter install
  config.py        knobs + first-run template
  theme.py         world80 rice-follow engine (lifted from beryl)
  ipc.py           single-instance socket → raise the window
  webprofile.py    the persistent Chromium profile (UA, SSO cookies, notifications)
  media.py         screen-share bridge: resolves the picked source by row
  api.py           Python↔view JS seam (request/response over signals)
  keys.py          modal KeyController + the native KeyFilter (vim entry point)
  commands.py      command registry + ex-line handler
  hints.py         hint-mode session state
  js/
    hints.js       f link-hints, isolated world, recurses same-origin iframes
    nav.js         j/k/d/u scroll targeting Teams' inner panes + c/e/a/s app-bar jumps
    editable.js    reports focus in/out of text fields → insert mode
    qwebchannel.js vendored transport for editable.js
  qml/
    Main.qml         root window: view + status line + cmdline + dispatch
    WebView.qml      the Teams view + transparency engine + permissions + media
    TitleBar.qml     world80 glass titlebar
    StatusBar.qml    vim mode + pending-keys line
    CmdLine.qml      the : / cmdline
    HelpOverlay.qml  the h key sheet, rendered from the live bind table
    ScreenPicker.qml screen/window chooser for getDisplayMedia  ← the gate
    PopupWindow.qml  auth / join-meeting popups on the shared profile
```
