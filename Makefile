APP_NAME := VoicePilot
DIST_DIR := dist
DEBUG_APP := $(DIST_DIR)/debug/$(APP_NAME).app
RELEASE_APP := $(DIST_DIR)/release/$(APP_NAME).app
INFO_PLIST := Sources/VoicePilot/Info.plist
ENTITLEMENTS := Sources/VoicePilot/VoicePilot.entitlements
ICON_PNG := dist/icon/AppIcon.png
ICON_ICNS := dist/icon/AppIcon.icns
SIGN_IDENTITY ?= -

DEBUG_BIN := $(shell swift build --show-bin-path)/$(APP_NAME)
RELEASE_BIN := $(shell swift build -c release --show-bin-path)/$(APP_NAME)

.PHONY: debug release bundle icon run install clean

debug:
	swift build
	$(MAKE) bundle APP_DIR="$(DEBUG_APP)" EXEC="$(DEBUG_BIN)"

release:
	swift build -c release
	$(MAKE) bundle APP_DIR="$(RELEASE_APP)" EXEC="$(RELEASE_BIN)"

icon:
	mkdir -p dist/icon
	cp Assets/AppIcon.png "$(ICON_PNG)"
	rm -rf /tmp/VoicePilot.iconset
	mkdir /tmp/VoicePilot.iconset
	sips -z 16 16     "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_16x16.png >/dev/null
	sips -z 32 32     "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_16x16@2x.png >/dev/null
	sips -z 32 32     "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_32x32.png >/dev/null
	sips -z 64 64     "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_32x32@2x.png >/dev/null
	sips -z 128 128   "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_128x128.png >/dev/null
	sips -z 256 256   "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256   "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_256x256.png >/dev/null
	sips -z 512 512   "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512   "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_512x512.png >/dev/null
	sips -z 1024 1024 "$(ICON_PNG)" --out /tmp/VoicePilot.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns /tmp/VoicePilot.iconset -o "$(ICON_ICNS)"
	rm -rf /tmp/VoicePilot.iconset

bundle: icon
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$(EXEC)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp "$(INFO_PLIST)" "$(APP_DIR)/Contents/Info.plist"
	cp "$(ICON_ICNS)" "$(APP_DIR)/Contents/Resources/AppIcon.icns"
	codesign --force --sign "$(SIGN_IDENTITY)" --entitlements "$(ENTITLEMENTS)" "$(APP_DIR)"

run: debug
	open "$(DEBUG_APP)"

install: release
	rm -rf /Applications/$(APP_NAME).app
	cp -R "$(RELEASE_APP)" /Applications/$(APP_NAME).app

clean:
	swift package clean
	rm -rf .build "$(DIST_DIR)"
