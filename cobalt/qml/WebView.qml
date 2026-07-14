import QtQuick
import QtWebChannel
import QtWebEngine

// The one Teams view. The transparency engine is lifted from beryl (built for
// Azure's iframe-heavy portal, which is exactly Teams' shape): it strips
// backgrounds and repaints text in the rice palette, injected into EVERY frame
// (runsOnSubFrames) and reaching into same-origin iframes from the parent —
// which is what lets it theme Teams' content where an Electron insertCss can't.
WebEngineView {
    id: view

    profile: WebProfile
    url: Config.url
    // transparent mode sits on the bare window glass so Hyprland blur shows;
    // opaque mode uses the rice bg to kill the white flash
    backgroundColor: Config.transparent ? "transparent" : Theme.viewBg

    settings.screenCaptureEnabled: true         // getDisplayMedia (the whole point)
    settings.fullScreenSupportEnabled: true      // meeting fullscreen
    settings.playbackRequiresUserGesture: false  // ringtones / call sounds autoplay
    settings.focusOnNavigationEnabled: true

    // --- permissions: auto-allow cam/mic/notifications for Teams; screen SHARE
    // is never here (it comes through desktopMediaRequested + the picker) ------
    onPermissionRequested: function (permission) {
        // scoped enum (enforcesScopedEnums) — bare WebEnginePermission.X is
        // undefined, which silently turned this whole handler into deny-all
        var P = WebEnginePermission.PermissionType
        var t = permission.permissionType
        var isMedia = t === P.MediaAudioCapture || t === P.MediaVideoCapture
                    || t === P.MediaAudioVideoCapture
                    || t === P.DesktopAudioVideoCapture || t === P.DesktopVideoCapture
        var benign = t === P.Notifications || t === P.ClipboardReadWrite
        if (benign || (isMedia && Config.auto_grant_media))
            permission.grant()
        else
            permission.deny()
    }

    onDesktopMediaRequested: function (request) {
        Media.present(request)
        picker.forceActiveFocus()
    }

    onNewWindowRequested: function (request) {
        popupComponent.createObject(view, { "request": request })
    }

    onFullScreenRequested: function (request) {
        request.accept()
        Window.window.visibility = request.toggleOn ? Window.FullScreen : Window.Windowed
    }

    onFindTextFinished: function (result) {
        api.findResult(result.numberOfMatches, result.activeMatch)
    }

    onLoadingChanged: function (info) {
        if (info.status !== WebEngineLoadingInfo.LoadSucceededStatus)
            return
        if (App.customCss.length > 0)
            runJavaScript(
                "(function(){var s=document.getElementById('cobalt-css')"
                + "||document.createElement('style');s.id='cobalt-css';"
                + "s.textContent=" + JSON.stringify(App.customCss) + ";"
                + "document.head.appendChild(s);})();")
        applyTransparentTheme()
    }

    // editable.js posts page focus over the channel → Python flips insert mode
    webChannel: WebChannel { registeredObjects: [pageBridge] }
    readonly property QtObject pageBridge: QtObject {
        WebChannel.id: "bridge"
        function editableFocused(on) { Vim.pageEditable(on === true) }
    }

    // re-skin live on a rice switch. Qt.callLater: QML Connections handlers run
    // BEFORE the python slot that resets the Theme context property, so defer
    // one turn to read the refreshed palette (the beryl retheme gotcha).
    Connections {
        target: Rice
        function onThemeChanged() { Qt.callLater(view.applyTransparentTheme) }
    }

    // config live-reload (page_scrim / page_colors changed): the
    // Config context property is re-set just before this fires, so defer a turn
    // to read the fresh values (same ordering as the theme path)
    Connections {
        target: App
        function onReskinRequested() { Qt.callLater(view.applyTransparentTheme) }
    }

    Component {
        id: popupComponent
        PopupWindow {}
    }

    // ---- transparency engine (lifted from beryl) -----------------------------
    // Only background-color is cleared, so images survive; text is repainted in
    // the rice palette (a site's near-black text would vanish on dark frost).
    function transparentTheme() {
        function rgba(c, a) {
            var k = Qt.color(c)
            return "rgba(" + Math.round(k.r * 255) + "," + Math.round(k.g * 255) + ","
                 + Math.round(k.b * 255) + "," + (a !== undefined ? a : k.a).toFixed(2) + ")"
        }
        function cssRgb(c) {
            var k = Qt.color(c)
            return "rgb(" + Math.round(k.r * 255) + ", " + Math.round(k.g * 255) + ", "
                 + Math.round(k.b * 255) + ")"
        }
        function cssRgba(c, a) {
            var k = Qt.color(c)
            return "rgba(" + Math.round(k.r * 255) + ", " + Math.round(k.g * 255) + ", "
                 + Math.round(k.b * 255) + ", " + a + ")"
        }
        function relLum(c) {
            function lin(u) { return u <= 0.03928 ? u / 12.92 : Math.pow((u + 0.055) / 1.055, 2.4) }
            var k = Qt.color(c)
            return 0.2126 * lin(k.r) + 0.7152 * lin(k.g) + 0.0722 * lin(k.b)
        }
        function legible(c, wantDark) {
            var k = Qt.color(c)
            var p = wantDark ? 1 : 0
            for (var i = 0; i < 30; i++) {
                if (wantDark ? relLum(k) >= 0.5 : relLum(k) <= 0.3)
                    break
                k = Qt.rgba(k.r + (p - k.r) * 0.1, k.g + (p - k.g) * 0.1,
                            k.b + (p - k.b) * 0.1, 1)
            }
            return k
        }
        // pull a colour toward the accent by t (0..1) so the page text carries
        // the theme's hue instead of reading as flat off-white
        function mix(a, b, t) {
            var ka = Qt.color(a), kb = Qt.color(b)
            return Qt.rgba(ka.r + (kb.r - ka.r) * t, ka.g + (kb.g - ka.g) * t,
                           ka.b + (kb.b - ka.b) * t, 1)
        }
        var mode = Config.page_colors || "auto"
        var dark = mode === "auto" ? Qt.color(Theme.bg).hslLightness < 0.5 : mode === "dark"
        var auto = mode === "auto"
        // ALL text is the rice theme's accent, legibility-clamped so it stays
        // readable on the frost — every glyph carries the theme's signature
        // colour (honey gold on nature, ice-blue on moon, ink on shiro, ...)
        var textC = auto ? legible(Theme.accent, dark) : (dark ? "#eceff4" : "#1a1b22")
        // placeholders read as a softened accent so they're clearly secondary
        var subC  = auto ? legible(mix(Theme.accent, Theme.text, 0.40), dark)
                         : (dark ? "#b2b8c8" : "#5c5e6e")
        var linkC = legible(Theme.accent, dark)
        var text = rgba(textC, 1)
        var sub = rgba(subC, 1)
        // borders/dividers/bubble outlines carry the accent too, so the whole
        // UI reads themed rather than just the glyphs
        var borderC = auto ? mix(Theme.text, Theme.accent, 0.6) : Theme.text
        var border = auto ? rgba(borderC, 0.30)
                          : (dark ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.15)")
        function capped(c, cap) {
            var k = Qt.color(c)
            return "rgba(" + Math.round(k.r * 255) + "," + Math.round(k.g * 255) + ","
                 + Math.round(k.b * 255) + "," + Math.min(k.a, cap).toFixed(2) + ")"
        }
        var field = auto ? capped(Theme.card, 0.35)
                         : (dark ? "rgba(16,18,26,0.35)" : "rgba(255,255,255,0.40)")
        var cardC = auto ? Theme.card : (dark ? "#10121a" : "#ffffff")
        var halo = dark ? "0 0 2px rgba(0,0,0,0.85),0 1px 6px rgba(0,0,0,0.55)"
                        : "0 0 2px rgba(255,255,255,0.90),0 1px 6px rgba(255,255,255,0.65)"
        var css = "html,body{background:transparent !important;}"
             + "*{background-color:transparent !important;"
             + "color:" + text + " !important;"
             + "-webkit-text-fill-color:currentcolor !important;"
             + "border-color:" + border + " !important;"
             + "text-shadow:" + halo + " !important;"
             + "box-shadow:none !important;"
             + "scrollbar-color:auto !important;scrollbar-width:auto !important;}"
             + "a,a *{color:" + rgba(linkC, 1) + " !important;}"
             + "::selection{background-color:" + rgba(linkC, 0.30) + " !important;}"
             + "::-webkit-scrollbar{width:10px;height:10px;background:transparent !important;}"
             + "::-webkit-scrollbar-track,::-webkit-scrollbar-corner{background:transparent !important;}"
             + "::-webkit-scrollbar-thumb{background-color:" + rgba(linkC, 0.40)
             + " !important;border-radius:5px;border:2px solid transparent !important;"
             + "background-clip:padding-box !important;}"
             + "::-webkit-scrollbar-thumb:hover,::-webkit-scrollbar-thumb:active{background-color:"
             + rgba(linkC, 0.70) + " !important;}"
             + "::-webkit-scrollbar-button{display:none !important;}"
             + "input,textarea,select{background-color:" + field
             + " !important;text-shadow:none !important;}"
             + "button{text-shadow:none !important;}"
             + "img,picture,video,canvas,svg,iframe,embed,object{text-shadow:none !important;}"
             + "::placeholder{color:" + sub + " !important;}"
             + ":root{color-scheme:" + (dark ? "dark" : "light") + " !important;}"
             + "[data-cobalt-ng-b]::before{background-image:none !important;}"
             + "[data-cobalt-ng-a]::after{background-image:none !important;}"
        return { css: css,
                 pal: { text: cssRgb(textC), link: cssRgb(linkC), sub: cssRgb(subC),
                        card: cssRgba(cardC, 0.85),
                        shadow: dark ? "0 8px 24px rgba(0,0,0,0.45)"
                                     : "0 8px 24px rgba(0,0,0,0.20)" } }
    }

    function transparentScript() {
        var t = transparentTheme()
        return `
(function () {
    if (window.__cobaltTransparent) return;
    window.__cobaltTransparent = true;
    var css = ${JSON.stringify(t.css)};
    window.__cobaltPal = ${JSON.stringify(t.pal)};
    window.__cobaltCss = css;
    window.__cobaltSheets = [];
    window.__cobaltRoots = [document];
    try {
        var s = new CSSStyleSheet();
        s.replaceSync(css);
        document.adoptedStyleSheets = document.adoptedStyleSheets.concat(s);
        window.__cobaltSheet = s;
        window.__cobaltSheets.push(s);
    } catch (e) {
        var ts = document.createElement("style");
        ts.id = "__cobalt_style";
        ts.textContent = css;
        (document.head || document.documentElement).appendChild(ts);
    }
    function gradOnly(bi) {
        return bi && bi.indexOf("gradient(") >= 0 && bi.indexOf("url(") < 0;
    }
    var OBS = { childList: true, subtree: true, attributes: true,
                attributeFilter: ["class", "style", "open",
                                  "data-theme", "data-color-mode", "data-bs-theme"] };
    var observer = null;
    function adoptInto(target, realmWin) {
        try {
            var sh = new realmWin.CSSStyleSheet();
            sh.replaceSync(window.__cobaltCss);
            target.adoptedStyleSheets = target.adoptedStyleSheets.concat(sh);
            window.__cobaltSheets.push(sh);
            return true;
        } catch (e) { return false; }
    }
    function themeFrame(fr) {
        var doc;
        try { doc = fr.contentDocument; } catch (e) { return; }
        if (!doc || !doc.documentElement
                || doc.documentElement.dataset.cobaltTransparent) return;
        doc.documentElement.dataset.cobaltTransparent = "1";
        try { if (fr.contentWindow) fr.contentWindow.__cobaltTransparent = true; }
        catch (e) {}
        if (!adoptInto(doc, doc.defaultView)) {
            var st = doc.createElement("style");
            st.textContent = window.__cobaltCss;
            (doc.head || doc.documentElement).appendChild(st);
        }
        window.__cobaltRoots.push(doc);
        if (observer) observer.observe(doc.documentElement, OBS);
        queue(sweeps, doc.documentElement);
    }
    function hookFrame(fr) {
        themeFrame(fr);
        if (!fr.__cobaltHook) {
            fr.__cobaltHook = 1;
            fr.addEventListener("load", function () { themeFrame(fr); });
        }
    }
    function adoptShadow(sr) {
        if (sr.__cobalt) return;
        sr.__cobalt = 1;
        adoptInto(sr, window);
        window.__cobaltRoots.push(sr);
        if (observer) observer.observe(sr, OBS);
        queue(sweeps, sr);
    }
    var ROLES = /^(dialog|alertdialog|menu|listbox|tooltip)$/;
    function surface(el, cs, win) {
        var out = cs.position === "fixed" || cs.position === "absolute";
        var tagged = ROLES.test((el.getAttribute && el.getAttribute("role")) || "")
                  || (el.matches && el.matches("dialog,[popover]"));
        // tagged surfaces (role=menu/dialog/listbox/tooltip, [popover]) qualify
        // regardless of their OWN position: Fluent UI (Teams, the Azure portal)
        // puts the role on a statically-positioned popover inside a fixed
        // wrapper, so requiring position on the tagged element let Teams' menus
        // slip through and get stripped see-through. Untagged floats still need
        // fixed/absolute + a real z-index.
        if (!(tagged || (out && (parseInt(cs.zIndex, 10) || 0) >= 100)))
            return null;
        if (cs.pointerEvents === "none" || cs.visibility === "hidden")
            return null;
        var r = el.getBoundingClientRect();
        if (r.width < 40 || r.height < 16) return null;
        if (r.width >= win.innerWidth * 0.95 && r.height >= win.innerHeight * 0.95)
            return null;
        // a real popup never exceeds the viewport; Teams' virtualized message
        // list body is absolute + z-indexed + thousands of px tall, and carding
        // it blacks out the whole chat column during scroll
        if (r.height > win.innerHeight * 1.2) return null;
        return r;
    }
    function strip(el) {
        var win = (el.ownerDocument && el.ownerDocument.defaultView) || window;
        var cs = win.getComputedStyle(el);
        var pal = window.__cobaltPal || {};
        var surf = pal.card ? surface(el, cs, win) : null;
        if (surf) {
            if (el.dataset.cobaltCard !== pal.card) {
                el.dataset.cobaltCard = pal.card;
                el.style.setProperty("background-color", pal.card, "important");
                el.style.setProperty("box-shadow", pal.shadow, "important");
                if (surf.width < win.innerWidth * 0.9)
                    el.style.setProperty("backdrop-filter", "blur(16px)", "important");
            }
        } else if (el.dataset.cobaltCard) {
            delete el.dataset.cobaltCard;
            el.style.removeProperty("background-color");
            el.style.removeProperty("box-shadow");
            el.style.removeProperty("backdrop-filter");
        }
        var bc = cs.backgroundColor;
        if (!surf && bc && bc !== "rgba(0, 0, 0, 0)" && bc !== "transparent"
                && !/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)
                && el.style.getPropertyValue("background-color") !== "transparent")
            el.style.setProperty("background-color", "transparent", "important");
        var col = cs.color;
        if (pal.text && col && !/,\\s*0\\)$/.test(col)
                && col !== pal.text && col !== pal.link && col !== pal.sub) {
            var want = (el.closest && el.closest("a")) ? pal.link : pal.text;
            el.style.setProperty("color", want, "important");
        }
        if (gradOnly(cs.backgroundImage))
            el.style.setProperty("background-image", "none", "important");
        if (cs.backgroundImage.indexOf("url(") >= 0) {
            var r = el.getBoundingClientRect();
            if (r.width >= win.innerWidth * 0.9 && r.height >= win.innerHeight * 0.85)
                el.style.setProperty("background-image", "none", "important");
        }
        if (gradOnly(win.getComputedStyle(el, "::before").backgroundImage))
            el.setAttribute("data-cobalt-ng-b", "");
        if (gradOnly(win.getComputedStyle(el, "::after").backgroundImage))
            el.setAttribute("data-cobalt-ng-a", "");
        if (el.tagName === "IFRAME" || el.tagName === "FRAME")
            hookFrame(el);
        if (el.shadowRoot)
            adoptShadow(el.shadowRoot);
    }
    function sweep(root) {
        if (root.nodeType === 1) {
            if (!root.isConnected) return;
            strip(root);
        }
        var els = root.querySelectorAll ? root.querySelectorAll("*") : [];
        for (var i = 0; i < els.length; i++) strip(els[i]);
    }
    var sweeps = new Set(), strips = new Set(), scheduled = false;
    function flush() {
        scheduled = false;
        sweeps.forEach(sweep);
        strips.forEach(function (el) { if (el.isConnected) strip(el); });
        sweeps.clear();
        strips.clear();
    }
    function queue(set, n) {
        set.add(n);
        if (!scheduled) { scheduled = true; setTimeout(flush, 120); }
    }
    function init() {
        observer = new MutationObserver(function (muts) {
            for (var i = 0; i < muts.length; i++) {
                var m = muts[i];
                if (m.type === "attributes") { queue(strips, m.target); continue; }
                for (var j = 0; j < m.addedNodes.length; j++) {
                    var n = m.addedNodes[j];
                    if (n.nodeType !== 1) continue;
                    queue(sweeps, n);
                    if (n.tagName === "LINK" || n.tagName === "STYLE")
                        n.addEventListener("load",
                            function () { queue(sweeps, document); }, { once: true });
                }
            }
        });
        observer.observe(document.documentElement, OBS);
        sweep(document);
        window.addEventListener("load",
            function () { queue(sweeps, document); }, { once: true });
        window.__cobaltResweep = function () {
            window.__cobaltRoots = window.__cobaltRoots.filter(function (r) {
                return r.nodeType === 9 ? r.defaultView : r.host && r.host.isConnected;
            });
            window.__cobaltRoots.forEach(function (r) { queue(sweeps, r); });
        };
        document.documentElement.dataset.cobaltTransparent = "1";
    }
    if (document.documentElement)
        init();
    else
        document.addEventListener("DOMContentLoaded", init);
})();`
    }

    function applyTransparentTheme() {
        if (!Config.transparent)
            return
        var t = transparentTheme()
        var css = JSON.stringify(t.css)
        runJavaScript("window.__cobaltPal=" + JSON.stringify(t.pal) + ";"
                      + "window.__cobaltCss=" + css + ";"
                      + "if(window.__cobaltSheets){window.__cobaltSheets.forEach("
                      + "function(s){try{s.replaceSync(" + css + ")}catch(e){}});}"
                      + "else if(window.__cobaltSheet){window.__cobaltSheet.replaceSync(" + css + ");}"
                      + "var t=document.getElementById('__cobalt_style');"
                      + "if(t)t.textContent=" + css + ";"
                      + "if(window.__cobaltResweep)window.__cobaltResweep();")
    }

    userScripts.collection: {
        var scripts = [
            {
                name: "qwebchannel",
                sourceUrl: Qt.resolvedUrl("../js/qwebchannel.js"),
                injectionPoint: WebEngineScript.DocumentCreation,
                worldId: WebEngineScript.MainWorld
            },
            {
                name: "editable",
                sourceUrl: Qt.resolvedUrl("../js/editable.js"),
                injectionPoint: WebEngineScript.DocumentReady,
                worldId: WebEngineScript.MainWorld
            },
            {
                name: "hints",
                sourceUrl: Qt.resolvedUrl("../js/hints.js"),
                injectionPoint: WebEngineScript.DocumentReady,
                worldId: WebEngineScript.ApplicationWorld
            },
            {
                name: "nav",
                sourceUrl: Qt.resolvedUrl("../js/nav.js"),
                injectionPoint: WebEngineScript.DocumentReady,
                worldId: WebEngineScript.ApplicationWorld
            }
        ]
        if (Config.transparent) {
            var src = transparentScript()
            scripts.push({
                name: "transparent-early",
                sourceCode: src,
                injectionPoint: WebEngineScript.DocumentCreation,
                worldId: WebEngineScript.MainWorld,
                runsOnSubFrames: true
            })
            scripts.push({
                name: "transparent-ready",
                sourceCode: src,
                injectionPoint: WebEngineScript.DocumentReady,
                worldId: WebEngineScript.MainWorld,
                runsOnSubFrames: true
            })
        }
        return scripts
    }
}
