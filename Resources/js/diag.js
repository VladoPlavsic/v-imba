/*
 * Diagnostics for hint mode, reached with `:diag [seconds] [text]`.
 *
 * Hint problems are invisible from the outside: a label that is present but
 * unstyled looks exactly like a label that was never created, and an element
 * in a cross-origin frame looks exactly like an element the xpath missed.
 * This reports the facts that tell those cases apart, into
 * ~/.config/vimba/diag.log.
 */

/* Must stay in step with the otY entry of hints.js's xpathmap. */
var VIMBA_HINT_XPATH = "//*[@href] | //*[@onclick or @tabindex or @class='lk' or @role='link' or @role='button' or @role='menuitem' or @role='tab' or @role='option'] | //*[@data-vimbaclick] | //input[not(@type='hidden' or @disabled or @readonly)] | //textarea[not(@disabled or @readonly)] | //button | //select | //summary";

function vimbaDiagnose(needle) {
    var out = {
        href: location.href.substr(0, 120),
        time: new Date().toISOString()
    };

    function rect(e) {
        var r = e.getBoundingClientRect();
        return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
    }

    function matchCount(doc) {
        try {
            return doc.evaluate(VIMBA_HINT_XPATH, doc, null,
                XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null).snapshotLength;
        } catch (ex) {
            return "error: " + ex;
        }
    }

    /* 1. Frames. A cross-origin frame is invisible to the main frame's
     * hints.js, which is the usual reason a menu cannot be hinted at all. */
    out.frames = [].map.call(document.querySelectorAll("iframe, frame"), function (f) {
        var info = {
            src: (f.src || "").substr(0, 90),
            rect: rect(f),
            /* A sandbox without allow-scripts means no script of ours
             * can ever run in that frame, hinted or not. */
            sandbox: f.getAttribute("sandbox"),
            name: f.getAttribute("name") || f.id || null,
            srcdoc: f.hasAttribute("srcdoc")
        };
        try {
            var d = f.contentDocument;
            info.sameOrigin = !!d;
            if (d) {
                info.hintable = matchCount(d);
            }
        } catch (ex) {
            info.sameOrigin = false;
        }
        return info;
    });

    /* 2. How many elements this document offers hint mode. */
    if (window.vimbaMarkClickable) {
        vimbaMarkClickable();
    }
    out.markedClickable = document.querySelectorAll("[data-vimbaclick]").length;
    out.hintable = matchCount(document);

    /* 3. Create a real hint set and look at what came out. A label that is
     * present but invisible points at page CSS; no label at all points at
     * hints.js. */
    out.hintCSSBytes = window.vimbaHintCSS ? window.vimbaHintCSS.length : 0;
    try {
        hints.init("o", false, 500, "0123456789", false, false);
        var host = document.querySelector('div[vimbahint="container"]');
        out.container = !!host;
        out.hintedElements = document.querySelectorAll("[vimbahint]").length;
        if (host) {
            out.containerRect = rect(host);
            var root = host.shadowRoot;
            out.shadowRoot = !!root;
            out.adoptedSheets = root && root.adoptedStyleSheets
                ? root.adoptedStyleSheets.length : 0;
            var labels = (root || host).querySelectorAll("span");
            out.labels = labels.length;
            var shown = 0, l, i;
            for (i = 0; i < labels.length; i++) {
                if (labels[i].style.display !== "none") {
                    shown++;
                    if (!l) {
                        l = labels[i];
                    }
                }
            }
            out.labelsShown = shown;
            if (l) {
                var cs = getComputedStyle(l);
                out.label = {
                    text: l.innerText,
                    attr: l.getAttribute("vimbahint"),
                    rect: rect(l),
                    position: cs.position,
                    inset: cs.left + "," + cs.top,
                    display: cs.display,
                    visibility: cs.visibility,
                    opacity: cs.opacity,
                    color: cs.color,
                    fill: cs.webkitTextFillColor,
                    background: cs.backgroundColor,
                    font: cs.fontSize + " " + cs.fontFamily.substr(0, 30),
                    textIndent: cs.textIndent,
                    letterSpacing: cs.letterSpacing,
                    transform: cs.transform,
                    clip: cs.clipPath,
                    zIndex: cs.zIndex,
                    overflow: cs.overflow
                };
                /* What the user would actually see at the label's centre. */
                var r = l.getBoundingClientRect(),
                    top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
                out.label.topmostAtCentre = top
                    ? top.tagName + "." + String(top.className).substr(0, 40)
                    : null;
            }
        }
    } catch (ex) {
        out.hintError = String(ex);
    }
    try {
        hints.clear(true);
    } catch (ex) {
        out.clearError = String(ex);
    }

    /* 4. Where a given piece of text lives, so a missing menu entry can be
     * traced to the frame and element that holds it. */
    if (needle) {
        var found = [], all = document.querySelectorAll("*"), i, e, t;
        for (i = 0; i < all.length && found.length < 6; i++) {
            e = all[i];
            t = e.textContent || "";
            if (t.toLowerCase().indexOf(needle.toLowerCase()) >= 0 && e.children.length === 0) {
                var cs2 = getComputedStyle(e);
                found.push({
                    tag: e.tagName,
                    role: e.getAttribute("role"),
                    href: !!e.getAttribute("href"),
                    tabindex: e.getAttribute("tabindex"),
                    clickable: e.hasAttribute("data-vimbaclick"),
                    cursor: cs2.cursor,
                    display: cs2.display,
                    visibility: cs2.visibility,
                    rect: rect(e)
                });
            }
        }
        out.needle = needle;
        out.needleMatches = found;
    }

    return JSON.stringify(out, null, 1);
}
