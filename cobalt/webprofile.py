import subprocess
from pathlib import Path

from PySide6.QtWebEngineCore import qWebEngineChromiumVersion
from PySide6.QtWebEngineQuick import QQuickWebEngineProfile

from . import config


def _chrome_ua():
    """A plain Chrome-on-Linux UA with the real engine version. The stock
    string advertises QtWebEngine, which Teams treats as an unsupported browser
    (degraded/blocked login) — and blending in is the better fingerprint
    anyway. Override via config.user_agent if a feature insists on Edge."""
    v = qWebEngineChromiumVersion()
    if isinstance(v, (bytes, bytearray, memoryview)):
        v = bytes(v).decode()
    major = str(v).split(".")[0]
    return ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            f"(KHTML, like Gecko) Chrome/{major}.0.0.0 Safari/537.36")


def _cookie_filter(cfg):
    def accept(request):
        if not request.thirdParty:
            return True
        # read cfg per call, not captured at boot: adding an SSO domain should
        # work without a restart
        allow = cfg.get("cookie_allow_3p", [])
        host = request.origin.host()
        return any(host == d or host.endswith("." + d) for d in allow)
    return accept


def _notify(notification):
    """Web Notifications → the desktop, so a message or a call ring taps the
    shoulder even when cobalt's window is hidden in the background."""
    try:
        subprocess.Popen(["notify-send", "-a", "cobalt", "-i", "cobalt",
                          notification.title() or "Teams",
                          notification.message() or ""])
    except OSError:
        pass
    notification.show()


def _on_download(cfg):
    def adopt(item):
        d = Path(cfg.get("download_dir", "~/Downloads")).expanduser()
        try:
            d.mkdir(parents=True, exist_ok=True)
            item.setDownloadDirectory(str(d))
        except OSError:
            pass
        item.accept()
    return adopt


def build(cfg, parent=None):
    """The one persistent Chromium profile for Teams. Persistent (not
    off-the-record) so the login survives restarts — that's the whole point of
    a dedicated app over a throwaway tab. QML binds it via the WebProfile
    context property."""
    ua = cfg.get("user_agent") or _chrome_ua()

    # the storage name MUST be a constructor arg — a default-constructed profile
    # is off-the-record (in-memory) forever, and setStorageName after the fact
    # does NOT switch it to persistent. Passing it here is what makes the Teams
    # login / cookies / cache survive a restart.
    profile = QQuickWebEngineProfile(
        "cobalt", parent,
        persistentStoragePath=str(config.DATA_HOME / "profile"),
        cachePath=str(config.CACHE_HOME / "webcache"),
        httpCacheType=QQuickWebEngineProfile.HttpCacheType.DiskHttpCache,
        persistentCookiesPolicy=QQuickWebEngineProfile.PersistentCookiesPolicy.AllowPersistentCookies,
        persistentPermissionsPolicy=QQuickWebEngineProfile.PersistentPermissionsPolicy.StoreOnDisk,
        httpUserAgent=ua)

    profile.presentNotification.connect(_notify)
    profile.downloadRequested.connect(_on_download(cfg))

    # third-party cookies blocked except the microsoft SSO domains — Teams
    # refreshes its tokens through login.microsoftonline.com iframes and dies
    # without them. IO thread — keep the callback pure.
    profile.cookieStore().setCookieFilter(_cookie_filter(cfg))

    return profile
