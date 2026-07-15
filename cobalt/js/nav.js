// cobalt: scroll helpers, isolated world (ApplicationWorld). Window scroll does
// nothing in Teams — its message list / rails are inner overflow panes — so
// j/k target the actual scroll container under the viewport centre, descending
// into same-origin iframes as needed. Falls back to the document scroller.
var __cobalt = window.__cobalt = window.__cobalt || {};

(function () {
    "use strict";

    function scrollable(el) {
        while (el && el.nodeType === 1) {
            var cs;
            try { cs = getComputedStyle(el); } catch (e) { break; }
            var oy = cs.overflowY;
            if ((oy === "auto" || oy === "scroll" || oy === "overlay")
                    && el.scrollHeight > el.clientHeight + 2)
                return el;
            el = el.parentElement;
        }
        return null;
    }

    function target() {
        var win = window, doc = document;
        for (var depth = 0; depth < 8; depth++) {
            var el;
            try { el = doc.elementFromPoint(win.innerWidth / 2, win.innerHeight / 2); }
            catch (e) { break; }
            if (!el) break;
            if (el.tagName === "IFRAME" || el.tagName === "FRAME") {
                var fdoc, fwin;
                try { fdoc = el.contentDocument; fwin = el.contentWindow; } catch (e) { fdoc = null; }
                if (fdoc && fwin) { doc = fdoc; win = fwin; continue; }
            }
            var sc = scrollable(el);
            if (sc) return sc;
            break;
        }
        return doc.scrollingElement || doc.documentElement || document.scrollingElement;
    }

    __cobalt.scroll = function (dy) {
        var t = target();
        if (t) t.scrollBy({ top: dy, behavior: "auto" });
    };
    __cobalt.scrollHalf = function (factor) {
        var t = target();
        if (t) t.scrollBy({ top: factor * t.clientHeight * 0.5, behavior: "auto" });
    };
    __cobalt.scrollEnd = function (sign) {
        var t = target();
        if (t) t.scrollTo({ top: sign > 0 ? t.scrollHeight : 0, behavior: "auto" });
    };

    // Teams' left app bar. Each button carries its app GUID as the id/data-tid,
    // so match those first — locale-independent, unlike the label. Chat ships
    // under two ids in the wild (the newer chat+channels app and the classic
    // one); aria-label is the last resort if a tenant pins something else.
    // Clicking the button is what Teams' own shortcuts do — no SPA reload.
    var RAIL = {
        activity: { ids: ["14d6962d-6eeb-4f48-8890-de55454bb136"], re: /^activity\b/i },
        chat:     { ids: ["3b64df9d-7e97-4d9c-ac5c-2e0a5d8e6f40",
                          "86fcd49b-61a2-4701-b771-54728cd291fb"], re: /^chat\b/i },
        calendar: { ids: ["ef56c0de-36fc-4ef8-b417-3d82ba9d073c"], re: /^calendar\b/i },
        calls:    { ids: ["20c3440d-c67e-4420-9f80-0e50c39693df"], re: /^calls\b/i },
    };

    function railButton(spec, root) {
        for (var i = 0; i < spec.ids.length; i++) {
            var byId = root.querySelector('[data-tid="' + spec.ids[i] + '"]');
            if (byId) return byId;
        }
        var btns = root.querySelectorAll("button[aria-label]");
        for (var j = 0; j < btns.length; j++)
            if (spec.re.test(btns[j].getAttribute("aria-label") || ""))
                return btns[j];
        return null;
    }

    __cobalt.rail = function (name) {
        var spec = RAIL[name];
        if (!spec) return false;
        var root = document.querySelector("[data-tid=app-bar-wrapper]") || document;
        var el = railButton(spec, root);
        if (!el) return false;
        el.click();
        return true;
    };
})();
