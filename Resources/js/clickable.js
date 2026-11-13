/*
 * Marks elements that behave as clickable but carry none of the attributes
 * hints.js matches on.
 *
 * Framework components attach their handlers with addEventListener, so they
 * have no href, onclick, role or tabindex, and vimb's xpath cannot see them.
 * CSS cursor is the reliable tell, which is the heuristic Vimium uses.
 */
function vimbaMarkClickable() {
    var previous = document.querySelectorAll("[data-vimbaclick]");
    for (var i = 0; i < previous.length; i++) {
        previous[i].removeAttribute("data-vimbaclick");
    }

    if (!document.body) {
        return;
    }

    var nodes = document.body.querySelectorAll("*"),
        vw = window.innerWidth,
        vh = window.innerHeight;

    for (var j = 0; j < nodes.length; j++) {
        var el = nodes[j];

        // Already matched by hints.js's own xpath.
        if (el.hasAttribute("href") || el.hasAttribute("onclick") ||
            el.hasAttribute("role") || el.hasAttribute("tabindex")) {
            continue;
        }

        if (window.getComputedStyle(el).cursor !== "pointer") {
            continue;
        }

        var rect = el.getBoundingClientRect();
        if (rect.width < 4 || rect.height < 4) {
            continue;
        }
        if (rect.bottom < 0 || rect.top > vh || rect.right < 0 || rect.left > vw) {
            continue;
        }

        // Nodes arrive in document order, so an ancestor is marked first;
        // skipping descendants avoids a hint per nested span.
        var parent = el.parentElement, nested = false;
        while (parent && parent !== document.body) {
            if (parent.hasAttribute("data-vimbaclick")) {
                nested = true;
                break;
            }
            parent = parent.parentElement;
        }
        if (nested) {
            continue;
        }

        el.setAttribute("data-vimbaclick", "");
    }
}

/*
 * Clicks whatever contains the current selection, which after a find is the
 * matched text. Lets `/` double as navigation: search for a link's words, then
 * press Enter to follow it.
 */
function vimbaFollowSelection() {
    var selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || !selection.anchorNode) {
        return false;
    }

    var node = selection.anchorNode,
        el = node.nodeType === 1 ? node : node.parentElement;

    while (el && el !== document.body) {
        var role = el.getAttribute && el.getAttribute("role");
        var clickable = el instanceof HTMLAnchorElement ||
            (el.hasAttribute && (el.hasAttribute("href") || el.hasAttribute("onclick") ||
                el.hasAttribute("data-vimbaclick"))) ||
            role === "button" || role === "link" ||
            el.tagName === "BUTTON" ||
            window.getComputedStyle(el).cursor === "pointer";

        if (clickable) {
            if (!(el instanceof HTMLAnchorElement)) {
                // Some components respond to the press, not the click.
                ["mousedown", "mouseup"].forEach(function (name) {
                    var event = new MouseEvent(name, {bubbles: true, cancelable: true, view: window});
                    el.dispatchEvent(event);
                });
            }
            el.click();
            return true;
        }
        el = el.parentElement;
    }

    return false;
}
