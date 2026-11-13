# Vimba

A keyboard-driven, modal web browser for macOS, built on Apple's WebKit.

It follows vim's model closely: modes rather than chords, buffers rather than a
tab bar, hint labels rather than the mouse. Every normal-mode binding lives in
a config file.

## Why it exists

[vimb](https://github.com/fanglingsu/vimb) is the inspiration, but vimb 4.x
needs `gtk4` and `webkitgtk-6.0`, and **WebKitGTK does not exist for macOS**:
Homebrew's formula is `depends_on :linux`, nixpkgs marks it broken on Darwin,
and MacPorts only carries the GTK3-era 2.28. Running it in a container and
viewing it over VNC works but feels like using a browser through a letterbox.

macOS already ships WebKit, so this targets `WKWebView` instead. That means
GPU-backed compositing, native fullscreen and real HiDPI — none of which the
container route could offer. vimb's hint-finding JavaScript is reused directly,
which is what made this tractable.

## Build

Requires Xcode and macOS 14+.

```sh
make            # build build/Vimba.app
make run        # build and run with console output attached
make install    # copy to /Applications, launchable from Spotlight
make config     # install the example keymap to ~/.config/vimba/
make icon       # regenerate the app icon from Resources/icon-source.svg
make uninstall  # remove the app, its saved state and preferences
```

Release is the default configuration; add `CONFIG=debug` for a debug build.

The app is assembled into a real `.app` bundle rather than run as a bare
executable, because `WKWebView` needs a bundle identifier to spawn its web
content process.

### Signing

Builds are ad-hoc signed by default. A **stable** signing identity is worth
setting up, because the keychain ACL WebKit creates for its WebCrypto master
key is pinned to the binary — with an ad-hoc signature the `cdhash` changes on
every build and macOS re-prompts each time. Put your identity in a local,
untracked `local.mk`:

```make
CODESIGN_IDENTITY = <sha-1 from `security find-identity -v -p codesigning`>
```

## Keys

Modes: **normal**, **insert**, **command**, **hint**, **pass-through**.
`Esc` always returns to normal.

### Normal mode

| Key | Action |
| --- | --- |
| `j` `k` | scroll down / up |
| `h` `l` | scroll left / right |
| `d` `u` | half page down / up |
| `gg` `G` | top / bottom |
| `H` `L` | history back / forward |
| `r` | reload |
| `i` | insert mode (keys reach the page) |
| `f` | hint mode |
| `/` `?` | search forward / backward |
| `n` `N` | repeat search, same / opposite direction |
| `Enter` | click whatever contains the selection |
| `:` | command bar |
| `o` `O` | command bar with `open ` / `open <current url>` |
| `y` | copy the current address to the clipboard |
| `gt` `gT` | next / previous buffer |
| `Ctrl-z` | pass-through mode |
| `Ctrl-=` `Ctrl--` `Ctrl-0` | zoom in / out / reset |
| `Esc` | blur the page, release the scroll target, close dropdowns |

`O` is how a mistyped address is corrected: it opens the command bar on the
current URL rather than an empty line. `Ctrl-p` in the command bar walks back
through what was submitted before, matching whatever is already typed, and
`Ctrl-n` walks forward again — the history is kept in `~/.config/vimba/history`
and survives restarts.

### Leader bindings

The leader is `<Space>`, and the `<leader>s…` namespace follows the kickstart
Telescope layout, so the muscle memory carries over from nvim:

| Keys | Opens |
| --- | --- |
| `<leader><leader>` | **[T]abs** — `n` new tab, `s` switch tab, `d` close tab |
| `<leader>b` | **[B]ookmarks** — `o` open here, `n` open in new tab, `d` delete, `s` save this page |
| `<leader>y` | **[Y]ank** — `f` full address, `r` path only |
| `<leader>p` | **[P]ath** — `e` edit, `o` open here, `y` copy |

Tabs sit on `<leader><leader>` because they are what a browser does most:
double-tap the leader, then one key. Everything else is grouped by what it
acts on, with the verbs constant throughout — `o` opens here, `n` opens in a
new buffer, `d` deletes, `s` saves or switches. `<leader>yf` and `<leader>yr`
mirror the full and relative path yanks in the nvim config: `yf` copies the
whole address, `yr` only the path, query and fragment.

Each one just opens the command bar prefilled, so Tab completion and fuzzy
matching work exactly as when the command is typed by hand.

Press `<Space>` and a which-key style panel lists what can follow it. Press a
group key and it narrows. It appears with no delay, matching `delay = 0` in
the nvim config, and `Esc` abandons a half-typed sequence without triggering
anything. It covers every multi-key binding, so `g` and `Ctrl-w` are
documented in place too.

**Shift-Enter submits to the other target.** `<leader>sb` opens a bookmark in a
new buffer on Enter and in the current one on Shift-Enter; the same swap turns
`:open` into `:tabnew` and back.

Arrow keys, `PgUp`/`PgDn`, `Home` and `End` are passed to the page even in
normal mode, so native `<select>` popups stay navigable. Any key with `Cmd` goes
to the menu bar untouched.

### Windows

| Key | Action |
| --- | --- |
| `Ctrl-w v` | split side by side |
| `Ctrl-w s` | split stacked |
| `Ctrl-w h` `k` | focus previous pane |
| `Ctrl-w l` `j` `w` | focus next pane |
| `Ctrl-w c` `q` | close pane (the buffer survives) |

### Hint mode

`f` labels every link, button and input. Then:

| Key | Action |
| --- | --- |
| `0`–`9` | narrow to a label |
| any other key | filter by link text |
| `Backspace` | undo the last filter character, then the last digit |
| `Enter` | follow the focused hint |
| `Esc` | cancel |

The status line shows what you have typed, so hints vanishing behind a filter is
visible rather than looking like a stuck mode. A digit that would match no hint
at all is ignored rather than clearing the screen, so a mistype costs nothing.

Hints cover **every frame of the page, including cross-origin ones**. That is
what makes Gmail's account menu or an embedded checkout form reachable: vimb's
hints.js can only walk same-origin subframes, so anything else was invisible to
it. The script runs in each frame instead and `HintController` coordinates
them — it tells each frame which number to carry on labelling from, so labels
stay unique across the whole page, and it makes sure a single frame holds the
focused hint, since otherwise one Enter would click in several frames at once.

### Pass-through mode

`Ctrl-z` hands the keyboard to the page until `Esc`. Normal mode deliberately
swallows unbound keys, which otherwise makes a web app's own keyboard shortcuts
unreachable.

## Commands

| Command | Aliases | Action |
| --- | --- | --- |
| `:open <target>` | `:o` `:op` | open in the current buffer |
| `:tabnew [target]` | `:t` `:tabopen` | open in a new buffer |
| `:b <query>` | `:buffer` | switch buffer by fuzzy name |
| `:bd [query]` | `:bdelete` `:tabclose` | delete a buffer |
| `:sbm <path>` | `:bookmark` | bookmark the current page at a path |
| `:obm <query>` | | open a bookmark |
| `:tobm <query>` | `:tbm` | open a bookmark in a new buffer |
| `:dbm <query>` | | delete a bookmark |
| `:cookies [filter]` | | list stored cookies with expiry, to stderr |
| `:diag [secs] [text]` | | write a hint-mode report to `~/.config/vimba/diag.log` |
| `:diag trace` | | log every hint call and its result; `:diag notrace` stops |
| `:quit` | `:q` | quit |

`:open` resolves a target three ways: something with a scheme is used as-is,
something with a dot gets `https://`, and anything else becomes a search.

### Completion

Press `Tab` in the command bar. The list is built **once** from what you typed
and then cycled, so repeated `Tab` walks the candidates instead of re-matching
against the text it just inserted. `Shift-Tab` and the arrow keys go backwards.
Nothing appears until you press `Tab`.

Matching is fzf-style: consecutive characters score higher, and a character
starting a path segment scores highest — which is why `gh` picks `github` over
`gitlab`. Tab is optional, since submitting re-runs the match.

Completion is offered for command names, bookmark paths (directories while
saving, whole paths while opening) and buffer names.

## Bookmarks

Bookmarks are addressed like a filesystem:

```
:sbm /social/video/youtube.com
:obm yt            → opens it
```

A path ending in `/` takes the page's host as its leaf, so `:sbm /social/` on
Facebook stores `/social/facebook.com`.

Stored as readable JSON at `~/.config/vimba/bookmarks.json`.

## Buffers and panes

Buffers are global and a pane shows one, exactly as in vim. `:b` switches the
**focused** pane. Closing a pane keeps its buffer; `:bd` deletes it.

Buffers are named automatically from `title — url`. They stay live so their
state survives switching, but any buffer not displayed in a pane is suspended
after 30 minutes idle, and reloads when you return to it.

Splitting shows a buffer that is not already on screen, or opens a new one at
the current URL if every buffer is visible — a `WKWebView` cannot appear in two
panes at once, so one buffer cannot be shown twice.

## Configuration

Everything lives under `~/.config/vimba/`:

| File | Holds |
| --- | --- |
| `config.json` | settings — start page, search engine, hint keys, zoom, timeouts |
| `keys.json` | bindings, the leader, and key-guide labels |
| `hints.css` | extra CSS appended after the built-in hint styling |
| `bookmarks.json` | bookmarks |
| `history` | submitted command lines, for `Ctrl-p` |
| `diag.log` | written by `:diag` |

`make config` writes `config.json` and `keys.json` from the example files
without overwriting anything already there. Both are read at launch only.

### Settings

`config.json` overrides what used to be compile-time constants; every key is
optional and falls back to the built-in value:

```json
{
  "start-page": "https://duckduckgo.com",
  "search-engine": "https://duckduckgo.com/",
  "window-chrome": "none",
  "window-width": 1280,
  "window-height": 800,
  "scroll-step": 60,
  "hint-keys": "0123456789",
  "max-hints": 500,
  "zoom-step": 1.1,
  "zoom-min": 0.3,
  "zoom-max": 5.0,
  "content-languages": ["en-US", "en"],
  "user-agent-suffix": "Version/18.0 Safari/605.1.15",
  "tab-idle-minutes": 30
}
```

The window has **no title bar** — no close, minimise or zoom buttons — so the
page runs to the top edge and the status line is the only furniture. It still
resizes from its edges and `⌘Q`, `⌘M` and `⌘W` still work, but with no title
bar there is nothing left to drag it by. `"window-chrome": "titled"` puts the
bar back.

`hint-keys` takes letters as readily as digits — `"asdfghjkl"` gives
Vimium-style home-row hints. The cost is that filtering hints by their text
stops working, since that is what any key outside `hint-keys` does.

`hints.css` is appended after the built-in stylesheet, so a rule there wins.
Label styling is also adopted into the shadow root the labels live in:

```css
span[vimbahint^='label'] { background: #16e06a !important; font-size: 18px !important; }
```


### Keys

`keys.json` merges over the built-in defaults, so you only list what you want
to change. A value is either an action name, or `command:<text>` to open the
command bar prefilled with that text, which is all a leader picker is. The
object form adds the label the key guide shows. `leader` sets what `<leader>`
stands for, and `groups` names the group rows in the guide:

```json
{
  "leader": "<Space>",
  "groups": { "<leader>s": "[S]earch", "<leader>b": "[B]uffer" },
  "normal": {
    "<C-d>": "half-page-down",
    "t": "command-open",
    "y": "yank-url",
    "<leader>sg": { "command": "open github.com/", "desc": "github" },
    "d": ""
  }
}
```

An empty string **removes** a binding. Notation follows vim: `gg`, `<C-w>v`,
`<C-d>`, `<Esc>`, `<CR>`, `<Tab>`, `<Space>`. Sequences resolve like vim's — a
partial match waits for more keys, an unknown one is discarded at once.

Available actions:

```
scroll-down  scroll-up  scroll-left  scroll-right
half-page-down  half-page-up  scroll-top  scroll-bottom
back  forward  reload
zoom-in  zoom-out  zoom-reset
insert-mode  hint-mode  passthrough-mode
command-mode  command-open  command-open-current  yank-url
search-forward  search-backward  search-next  search-previous
follow-selection
next-tab  previous-tab
split-vertical  split-horizontal  close-pane
focus-next-pane  focus-previous-pane
```

Only normal mode is bindable. The others are structural rather than keymaps:
insert mode passes everything to the page, command mode is text editing, and
hint mode is digits and filtering.

The file is read at launch; there is no live reload yet.

`Sources/vimba/Config.swift` holds the fallback for every setting, so the
built-in behaviour is readable in one place.

## Debugging

```sh
VIMBA_DEBUG=1 ./build/Vimba.app/Contents/MacOS/Vimba
```

Logs every keystroke with its mode, completion state, hint status and pane
geometry to stderr. This found three real bugs during development, including a
swallowed `NSException` that made working code look like it never ran.

`:diag` exists because hint failures are invisible from the outside: a label
that is present but unstyled looks exactly like a label that was never created,
and an element in a cross-origin frame looks exactly like one the xpath missed.
It creates a real hint set and reports the page's frames, how many elements the
xpath matched, and the first label's computed style and geometry. `:diag 8 add
account` waits 8 seconds first — long enough to open a menu — and then reports
where that text lives. `:diag trace` logs every call made to every frame and
what each answered, which is how the duplicate-frame bug was found.

When testing anything about sessions or cookies, quit with **⌘Q**. Killing the
app with `SIGTERM` stops WebKit flushing its cookie store, which looks exactly
like a session-persistence bug.

## Implementation notes

Modal input works by taking keys **before** the web view sees them, through a
per-window `NSEvent.addLocalMonitorForEvents`. `WKWebView` consumes every
keystroke while page content has focus, so nothing less gets first refusal.
Each window filters on `event.window`, which is what lets the browser window,
popups and panes coexist.

`hints.js` and `hints.css` come from vimb and carry the changes marked
`LOCAL CHANGE`:

- `open()` dispatches a real click instead of assigning `location.href`.
  Assigning it forces a full page load, which stops a single-page app routing
  client-side — links appeared to merely reload the page.
- The xpath also matches `data-vimbaclick`, set by `clickable.js` on elements
  whose only clue is `cursor: pointer`. Framework components attach handlers
  with `addEventListener` and so carry no `href`, `onclick`, `role` or
  `tabindex` for the original xpath to find.

Scrolling resolves a target before acting: the scrollable element under focus,
then the last clicked element, then the one under the pointer, then the largest
visible scrollable overlay, and only then the page. Dropdowns are usually
portaled to `<body>`, so they are ancestors of nothing focused — hence the
overlay search. `Esc` releases that target and keeps it released until you
click something.

## Known limitations

- **Split layout is flat**, one orientation at a time. `Ctrl-w s` after
  `Ctrl-w v` flips the window rather than nesting; true nesting needs a pane
  tree instead of a single `NSSplitView`.
- **Tab suspension reloads**, so scroll position is lost. `WKWebView` has no
  public state-freeze API.
- **YouTube signs you out roughly weekly.** WebKit's tracking prevention caps
  its auth cookies at 7 days, while the identical cookies on `google.com` keep
  13 months. There is no public API to change this.
- **Hints and `:` are unavailable in popups** — popups have modal input and
  start in insert mode, but no command bar.
- **No history store**, so `:open` offers no completion.
- **No vim motions inside text fields** yet. Feasible for `<textarea>`,
  `<input>` and `contenteditable` via `Selection.modify`; not feasible for
  editors that own their own caret, such as Google Docs.

## Licence

`hints.js` and `hints.css` are taken from vimb and are **GPL-3.0-or-later**, so
this project inherits GPL-3.0-or-later as a derivative work. `scroll.js` and
`clickable.js` are original to this project.
