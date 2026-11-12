# v-imba

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
make            # build build/Vimb.app
make run        # build and run with console output attached
make install    # copy to /Applications, launchable from Spotlight
make config     # install the example keymap to ~/.config/vimb-mac/
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
| `gt` `gT` | next / previous buffer |
| `Ctrl-z` | pass-through mode |
| `Ctrl-=` `Ctrl--` `Ctrl-0` | zoom in / out / reset |
| `Esc` | blur the page, release the scroll target, close dropdowns |

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
visible rather than looking like a stuck mode.

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

Stored as readable JSON at `~/.config/vimb-mac/bookmarks.json`.

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

> Config and data live under `~/.config/vimb-mac/`, which predates the rename
> to v-imba. Renaming the directory means moving existing bookmarks, so it has
> been left alone for now.


`~/.config/vimb-mac/keys.json` merges over the built-in defaults, so you only
list what you want to change:

```json
{
  "normal": {
    "<C-d>": "half-page-down",
    "t": "command-open",
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
command-mode  command-open  command-open-current
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

Other settings live in `Sources/vimbmac/Config.swift` — start page, search
engine, scroll step, zoom range, hint keys, idle timeout, user agent.

## Debugging

```sh
VIMB_DEBUG=1 ./build/Vimb.app/Contents/MacOS/Vimb
```

Logs every keystroke with its mode, completion state, hint status and pane
geometry to stderr. This found three real bugs during development, including a
swallowed `NSException` that made working code look like it never ran.

When testing anything about sessions or cookies, quit with **⌘Q**. Killing the
app with `SIGTERM` stops WebKit flushing its cookie store, which looks exactly
like a session-persistence bug.

## Implementation notes

Modal input works by taking keys **before** the web view sees them, through a
per-window `NSEvent.addLocalMonitorForEvents`. `WKWebView` consumes every
keystroke while page content has focus, so nothing less gets first refusal.
Each window filters on `event.window`, which is what lets the browser window,
popups and panes coexist.

`hints.js` and `hints.css` come from vimb and carry two changes, both marked
`LOCAL CHANGE`:

- `open()` dispatches a real click instead of assigning `location.href`.
  Assigning it forces a full page load, which stops a single-page app routing
  client-side — links appeared to merely reload the page.
- The xpath also matches `data-vimbclick`, set by `clickable.js` on elements
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
