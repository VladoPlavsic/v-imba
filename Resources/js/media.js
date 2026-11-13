/*
 * Whether this document is playing audible media.
 *
 * Suspending a tab navigates it to about:blank, which stops playback dead and
 * loses its place - so a background tab playing music must be left alone.
 * WebKit only exposes isPlayingAudio to web extensions, not to an embedder,
 * so the page is asked directly.
 */
function vimbaIsPlayingMedia() {
    function playing(doc) {
        var media = doc.querySelectorAll("audio, video"), i, m;
        for (i = 0; i < media.length; i++) {
            m = media[i];
            /* readyState rules out an element that is merely primed to play. */
            if (!m.paused && !m.ended && !m.muted && m.volume > 0 && m.readyState > 2) {
                return true;
            }
        }
        return false;
    }

    if (playing(document)) {
        return true;
    }
    /* Same-origin frames are reachable from here; a cross-origin frame runs
     * its own copy of this and is asked separately. */
    for (var i = 0; i < window.frames.length; i++) {
        try {
            if (window.frames[i].document && playing(window.frames[i].document)) {
                return true;
            }
        } catch (ex) {
            continue;
        }
    }
    return false;
}
