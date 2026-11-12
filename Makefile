# Machine-local overrides (signing identity, etc). Not tracked.
-include local.mk

APP      := Vimb
BUNDLE   := build/$(APP).app
CONFIG   ?= release
# A stable signing identity keeps the keychain ACL for WebKit's WebCrypto
# master key valid across rebuilds; ad-hoc ("-") changes on every build, so
# macOS re-prompts each time. Override with a self-signed certificate name.
CODESIGN_IDENTITY ?= -
BIN      := .build/$(CONFIG)/vimbmac

all: app

build:
	swift build -c $(CONFIG)

# WKWebView needs a real bundle identifier to spawn its web content process,
# so the executable is always assembled into an .app rather than run bare.
app: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp -R Resources/en.lproj $(BUNDLE)/Contents/Resources/
	@cp -R Resources/js $(BUNDLE)/Contents/Resources/
	codesign --force --sign $(CODESIGN_IDENTITY) $(BUNDLE)
	@echo "built $(BUNDLE) (signed: $(CODESIGN_IDENTITY))"

# Run the binary inside the bundle so stdout stays attached to the terminal.
run: app
	$(BUNDLE)/Contents/MacOS/$(APP)

# Install into /Applications so the app is launchable from Spotlight and the
# Dock like any other, rather than only from this directory.
install: app
	@rm -rf /Applications/$(APP).app
	@cp -R $(BUNDLE) /Applications/
	@echo "installed /Applications/$(APP).app"

uninstall:
	@rm -rf /Applications/$(APP).app
	@echo "removed /Applications/$(APP).app"

clean:
	rm -rf .build build

.PHONY: all build app run install uninstall config clean

# Copy the example keymap into place so it can be edited.
config:
	@mkdir -p $(HOME)/.config/vimb-mac
	@test -f $(HOME)/.config/vimb-mac/keys.json \
		|| cp keys.example.json $(HOME)/.config/vimb-mac/keys.json
	@echo "keymap: $(HOME)/.config/vimb-mac/keys.json"
