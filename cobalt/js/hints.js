// cobalt: link hints. Runs in an ISOLATED world (ApplicationWorld) so Teams
// can't see or clobber __cobalt, and Python drives every exchange through
// runJavaScript round-trips. Labels are fixed-position divs in a closed shadow
// root, so page CSS can't touch them. Unlike beryl's, this reaches into
// SAME-ORIGIN iframes (Teams renders much of its UI in them) and maps their
// element rects into the top viewport so labels land in the right place.
var __cobalt = window.__cobalt = window.__cobalt || {};

__cobalt.hints = (function () {
    "use strict";
    var host = null, items = [];
    var SEL = 'a[href], button, input:not([type=hidden]), textarea, select, summary,'
            + ' [onclick], [role=link], [role=button], [role=tab], [role=menuitem],'
            + ' [role=checkbox], [role=option], [role=treeitem], [role=switch],'
            + ' [contenteditable=""], [contenteditable=true],'
            + ' [tabindex]:not([tabindex="-1"])';

    function shown(el, cs) {
        return !(cs.visibility === "hidden" || cs.display === "none" || cs.opacity === "0");
    }

    // walk doc + its same-origin descendant frames; offX/offY accumulate each
    // frame's on-screen offset so rects land in the TOP window's viewport.
    function collect(doc, win, offX, offY, vw, vh, seen, out) {
        var els;
        try { els = doc.querySelectorAll(SEL); } catch (e) { return; }
        for (var i = 0; i < els.length; i++) {
            var el = els[i];
            if (seen.has(el)) continue;
            seen.add(el);
            var r = el.getBoundingClientRect();
            if (r.width < 2 || r.height < 2) continue;
            var left = r.left + offX, top = r.top + offY;
            if (top + r.height < 0 || top > vh || left + r.width < 0 || left > vw) continue;
            var cs;
            try { cs = win.getComputedStyle(el); } catch (e) { continue; }
            if (!shown(el, cs)) continue;
            out.push({ el: el, left: left, top: top });
        }
        var frames = doc.querySelectorAll("iframe, frame");
        for (var f = 0; f < frames.length; f++) {
            var fr = frames[f], fdoc, fwin;
            try { fdoc = fr.contentDocument; fwin = fr.contentWindow; } catch (e) { continue; }
            if (!fdoc || !fwin) continue;
            var fb = fr.getBoundingClientRect();
            collect(fdoc, fwin, offX + fb.left, offY + fb.top, vw, vh, seen, out);
        }
    }

    function clickables() {
        var seen = new Set(), out = [];
        collect(document, window, 0, 0, innerWidth, innerHeight, seen, out);
        return out;
    }

    // uniform-length base-k labels — prefix-free by construction
    function labels(n, alphabet) {
        var k = alphabet.length;
        var len = Math.max(1, Math.ceil(Math.log(n) / Math.log(k)));
        var out = [];
        for (var i = 0; i < n; i++) {
            var s = "", x = i;
            for (var j = 0; j < len; j++) { s = alphabet[x % k] + s; x = (x / k) | 0; }
            out.push(s);
        }
        return out;
    }

    function editable(el) {
        if (el.isContentEditable) return true;
        var t = el.tagName;
        if (t === "TEXTAREA" || t === "SELECT") return true;
        if (t === "INPUT")
            return !/^(button|checkbox|radio|submit|reset|file|image|range|color|hidden)$/
                .test((el.type || "text").toLowerCase());
        return false;
    }

    function show(alphabet) {
        clear();
        var els = clickables();
        if (els.length === 0) return 0;
        host = document.createElement("cobalt-hints");
        var root = host.attachShadow({ mode: "closed" });
        var box = document.createElement("div");
        box.style.cssText = "position:fixed;inset:0;z-index:2147483647;pointer-events:none;";
        var labs = labels(els.length, alphabet);
        els.forEach(function (c, i) {
            var d = document.createElement("div");
            d.textContent = labs[i];
            d.style.cssText =
                "position:fixed;left:" + Math.max(0, c.left - 2) + "px;top:" +
                Math.max(0, c.top - 2) + "px;background:#f8e08e;color:#1a1a1a;" +
                "font:bold 11px monospace;padding:1px 4px;border-radius:3px;" +
                "box-shadow:0 1px 3px rgba(0,0,0,.55);";
            box.appendChild(d);
            items.push({ el: c.el, label: labs[i], div: d });
        });
        root.appendChild(box);
        document.documentElement.appendChild(host);
        return els.length;
    }

    function filter(typed) {
        var live = 0;
        items.forEach(function (it) {
            var m = it.label.indexOf(typed) === 0;
            it.div.style.display = m ? "" : "none";
            if (m) live++;
        });
        return live;
    }

    function activate(typed) {
        // prefix match among still-visible hints: Python activates as soon as
        // one remains, and a unique prefix can be shorter than the label length
        var it = null;
        for (var i = 0; i < items.length; i++)
            if (items[i].label.indexOf(typed) === 0
                    && items[i].div.style.display !== "none") {
                it = items[i];
                break;
            }
        clear();
        if (!it) return { miss: true };
        var el = it.el;
        if (editable(el)) {
            el.focus();                     // editable.js flips us to insert
            return { focused: true };
        }
        el.focus();
        el.click();                         // full synthetic click, works on js-only buttons
        return { clicked: true };
    }

    function clear() {
        if (host) host.remove();
        host = null;
        items = [];
    }

    return { show: show, filter: filter, activate: activate, clear: clear };
})();

// gi — focus the first editable across same-origin frames
__cobalt.firstInput = function () {
    function look(doc) {
        var els;
        try {
            els = doc.querySelectorAll(
                'input:not([type=hidden]), textarea, [contenteditable=""], [contenteditable=true]');
        } catch (e) { return false; }
        for (var i = 0; i < els.length; i++) {
            var r = els[i].getBoundingClientRect();
            if (r.width > 2 && r.height > 2) { els[i].focus(); return true; }
        }
        var frames = doc.querySelectorAll("iframe, frame");
        for (var f = 0; f < frames.length; f++) {
            var fdoc;
            try { fdoc = frames[f].contentDocument; } catch (e) { continue; }
            if (fdoc && look(fdoc)) return true;
        }
        return false;
    }
    return look(document);
};
