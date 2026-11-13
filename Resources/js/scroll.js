/*
 * Element-aware scrolling.
 *
 * vimb's own scroll.js always ends in window.scrollTo, so a dropdown,
 * suggestion list, sidebar or modal with its own scroll area never responds to
 * j/k. Resolving the right element is the hard part: the mouse is wherever the
 * user left it, and dropdowns are often portaled to <body>, so they are not
 * ancestors of whatever has focus either. Hence the ordered fallbacks below,
 * ending in a search for a visible scrollable overlay.
 *
 * Whatever is chosen is briefly outlined, so it is never a mystery which box
 * just scrolled.
 */
var vimbaScroll = (function () {
    var pointer = {x: 0, y: 0},
        lastInteracted = null,
        flashTimer = null,
        /* Set by release(): forces scrolling back to the page until the user
         * deliberately interacts with something again. Without it the pointer
         * and overlay fallbacks below re-acquire the dropdown immediately. */
        forceWindow = false;

    window.addEventListener("mousemove", function (e) {
        pointer.x = e.clientX;
        pointer.y = e.clientY;
    }, true);

    function remember(e) {
        lastInteracted = e.target;
        forceWindow = false;
    }
    window.addEventListener("click", remember, true);
    window.addEventListener("focusin", remember, true);

    function isScrollable(el) {
        if (!el || el === document.body || el === document.documentElement) {
            return false;
        }
        if (el.nodeType !== 1) {
            return false;
        }
        var overflow = window.getComputedStyle(el).overflowY;
        return /(auto|scroll|overlay)/.test(overflow) &&
               el.scrollHeight > el.clientHeight + 1;
    }

    function ancestor(el) {
        while (el && el !== document.body && el !== document.documentElement) {
            if (isScrollable(el)) {
                return el;
            }
            el = el.parentElement;
        }
        return null;
    }

    /* A portaled dropdown is a visible scrollable box that is smaller than the
     * viewport. Pick the largest such box, which avoids latching onto tiny
     * scrollers while still ignoring the page shell itself. */
    function visibleOverlay() {
        if (!document.body) {
            return null;
        }
        var nodes = document.body.querySelectorAll("*"),
            vw = window.innerWidth,
            vh = window.innerHeight,
            viewport = vw * vh,
            best = null,
            bestArea = 0;

        for (var i = 0; i < nodes.length; i++) {
            var el = nodes[i];
            if (!isScrollable(el)) {
                continue;
            }
            var r = el.getBoundingClientRect();
            if (r.width < 40 || r.height < 40) {
                continue;
            }
            if (r.bottom < 0 || r.top > vh || r.right < 0 || r.left > vw) {
                continue;
            }
            var area = r.width * r.height;
            if (area < viewport * 0.95 && area > bestArea) {
                best = el;
                bestArea = area;
            }
        }
        return best;
    }

    function target() {
        if (forceWindow) {
            return null;
        }
        return ancestor(document.activeElement) ||
               ancestor(lastInteracted) ||
               ancestor(document.elementFromPoint(pointer.x, pointer.y)) ||
               visibleOverlay();
    }

    /* Outline the box that scrolled, so the target is never ambiguous. */
    function flash(el) {
        if (!el) {
            return;
        }
        el.setAttribute("vimbascroll", "active");
        window.clearTimeout(flashTimer);
        flashTimer = window.setTimeout(function () {
            el.removeAttribute("vimbascroll");
        }, 900);
    }

    function apply(fn, fallback) {
        var el = target();
        if (el) {
            fn(el);
            flash(el);
        } else {
            fallback();
        }
    }

    return {
        /* Forget the latched target so scrolling returns to the page. */
        release: function () {
            lastInteracted = null;
            forceWindow = true;
            window.clearTimeout(flashTimer);
            var marked = document.querySelectorAll("[vimbascroll]");
            for (var i = 0; i < marked.length; i++) {
                marked[i].removeAttribute("vimbascroll");
            }
        },
        by: function (dy) {
            apply(function (el) { el.scrollTop += dy; },
                  function () { window.scrollBy(0, dy); });
        },
        byX: function (dx) {
            apply(function (el) { el.scrollLeft += dx; },
                  function () { window.scrollBy(dx, 0); });
        },
        byPages: function (factor) {
            apply(function (el) { el.scrollTop += el.clientHeight * factor; },
                  function () { window.scrollBy(0, window.innerHeight * factor); });
        },
        toTop: function () {
            apply(function (el) { el.scrollTop = 0; },
                  function () { window.scrollTo(0, 0); });
        },
        toBottom: function () {
            apply(function (el) { el.scrollTop = el.scrollHeight; },
                  function () { window.scrollTo(0, document.body.scrollHeight); });
        }
    };
})();

/*
 * Escape in normal mode: drop DOM focus, release the scroll target, and pass a
 * synthetic Escape to the page so dropdowns and modals close. The real key
 * never reaches the page, because normal mode consumes it.
 */
function vimbaReleaseFocus() {
    if (document.activeElement && document.activeElement.blur) {
        document.activeElement.blur();
    }
    if (window.vimbaScroll) {
        window.vimbaScroll.release();
    }
    document.dispatchEvent(new KeyboardEvent("keydown", {
        key: "Escape",
        code: "Escape",
        keyCode: 27,
        which: 27,
        bubbles: true,
        cancelable: true
    }));
}
