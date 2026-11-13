# Machine-local overrides (signing identity, etc). Not tracked.
-include local.mk

APP      := Vimba
BUNDLE_ID := local.vimba
# Where WebKit and AppKit keep this app's state, all keyed by bundle id.
WEBKITDATA := $(HOME)/Library/WebKit/$(BUNDLE_ID)
WEBKITCACHE := $(HOME)/Library/Caches/$(BUNDLE_ID)
PREFS := $(HOME)/Library/Preferences/$(BUNDLE_ID).plist
SAVEDSTATE := $(HOME)/Library/Saved Application State/$(BUNDLE_ID).savedState
CONFIGDIR := $(HOME)/.config/vimba
BUNDLE   := build/$(APP).app
CONFIG   ?= release
# A stable signing identity keeps the keychain ACL for WebKit's WebCrypto
# master key valid across rebuilds; ad-hoc ("-") changes on every build, so
# macOS re-prompts each time. Override with a self-signed certificate name.
CODESIGN_IDENTITY ?= -
BIN      := .build/$(CONFIG)/vimba

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
	@# Stamp the names from this file, so the plist can never drift from the
	@# binary it describes. CFBundleExecutable must match MacOS/$(APP)
	@# exactly: on a case-insensitive disk a mismatch still opens the file,
	@# but codesign then seals it a second time as nested code and launchd
	@# refuses the bundle with "Launchd job spawn failed".
	@/usr/libexec/PlistBuddy \
		-c "Set :CFBundleExecutable $(APP)" \
		-c "Set :CFBundleName $(APP)" \
		-c "Set :CFBundleDisplayName $(APP)" \
		-c "Set :CFBundleIdentifier $(BUNDLE_ID)" \
		$(BUNDLE)/Contents/Info.plist >/dev/null
	@cp -R Resources/en.lproj $(BUNDLE)/Contents/Resources/
	@cp -R Resources/js $(BUNDLE)/Contents/Resources/
	@cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/
	codesign --force --sign $(CODESIGN_IDENTITY) $(BUNDLE)
	@# Fail here rather than at launch: an invalid signature is rejected by
	@# launchd with an error that says nothing about signing.
	codesign --verify --strict $(BUNDLE)
	@echo "built $(BUNDLE) (signed: $(CODESIGN_IDENTITY))"

# Run the binary inside the bundle so stdout stays attached to the terminal.
run: app
	$(BUNDLE)/Contents/MacOS/$(APP)

# Install into /Applications so the app is launchable from Spotlight and the
# Dock like any other, rather than only from this directory.
install: app
	@rm -rf /Applications/$(APP).app
	@cp -R $(BUNDLE) /Applications/
	@# Without this the Dock and Finder keep the icon they cached
	@# for the previous build.
	@touch /Applications/$(APP).app
	@echo "installed /Applications/$(APP).app"

# Removes the app and the state macOS keeps for it, but no browsing data and
# no bookmarks: see purge-cache and purge.
uninstall:
	@rm -rf /Applications/$(APP).app
	@rm -rf "$(SAVEDSTATE)"
	@rm -f "$(PREFS)"
	@echo "removed /Applications/$(APP).app, its saved state and preferences"
	@echo "kept browsing data; run 'make purge' to remove it"
	@echo "kept bookmarks and keymap in $(CONFIGDIR)"

# WebKit's cache grows into the hundreds of megabytes. Clearing it loses
# nothing: sessions, bookmarks and settings all survive.
purge-cache:
	@du -sh "$(WEBKITCACHE)" 2>/dev/null || true
	@rm -rf "$(WEBKITCACHE)"
	@echo "cleared WebKit cache"

# Removes all browsing data: cookies, local storage, IndexedDB and the
# keychain item WebKit uses to encrypt stored WebCrypto keys. You will be
# signed out of everything. Bookmarks and the keymap are kept deliberately,
# since they are the only things here that cannot be regenerated.
purge: uninstall purge-cache
	@rm -rf "$(WEBKITDATA)"
	@-security delete-generic-password -l "vimba WebCrypto Master Key" >/dev/null 2>&1 || true
	@echo "removed browsing data and the keychain item"
	@echo "bookmarks and keymap still in $(CONFIGDIR)"

# Regenerates the icon from Resources/icon-source.svg. Only needed when the
# artwork changes: Resources/icon.svg (text flattened to paths, so it does not
# depend on a font being installed) and Resources/AppIcon.icns are both
# checked in. Needs inkscape and rsvg-convert.
ICON_SIZES := 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
	128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 \
	512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x

icon:
	inkscape Resources/icon-source.svg --export-text-to-path \
		--export-plain-svg --export-filename=Resources/icon.svg
	@rm -rf build/AppIcon.iconset
	@mkdir -p build/AppIcon.iconset
	@for spec in $(ICON_SIZES); do \
		size=$${spec%%:*}; name=$${spec#*:}; \
		rsvg-convert -w $$size -h $$size Resources/icon.svg \
			-o "build/AppIcon.iconset/$$name.png"; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "wrote Resources/AppIcon.icns"

clean:
	rm -rf .build build

.PHONY: all build app run install uninstall purge-cache purge config icon clean

# Copy the example keymap into place so it can be edited.
config:
	@mkdir -p $(CONFIGDIR)
	@test -f $(CONFIGDIR)/keys.json || cp keys.example.json $(CONFIGDIR)/keys.json
	@test -f $(CONFIGDIR)/config.json || cp config.example.json $(CONFIGDIR)/config.json
	@echo "keymap:   $(CONFIGDIR)/keys.json"
	@echo "settings: $(CONFIGDIR)/config.json"
