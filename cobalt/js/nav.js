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
})();
