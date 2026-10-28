PREFIX ?= /usr/local
BUILD_DIR = .build/release
APP_NAME = Twinly.app
BUILD_APP = build/$(APP_NAME)
DMG_NAME = Twinly.dmg
BUILD_DMG = build/$(DMG_NAME)

.PHONY: all build test app dmg clean install

all: build

build:
	swift build -c release

test:
	swift run TwinlyTestsRunner

app: build
	@echo "Creating $(APP_NAME)..."
	@mkdir -p $(BUILD_APP)/Contents/MacOS
	@mkdir -p $(BUILD_APP)/Contents/Resources
	@mkdir -p $(BUILD_APP)/Contents/Helpers
	@cp $(BUILD_DIR)/Twinly $(BUILD_APP)/Contents/MacOS/Twinly
	@cp $(BUILD_DIR)/TwinlyLauncher $(BUILD_APP)/Contents/Helpers/TwinlyLauncher
	@cp $(BUILD_DIR)/TwinlyLauncher $(BUILD_APP)/Contents/Resources/TwinlyLauncher
	@cp Resources/Info.plist $(BUILD_APP)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(BUILD_APP)/Contents/Resources/AppIcon.icns
	@chmod +x $(BUILD_APP)/Contents/MacOS/Twinly
	@chmod +x $(BUILD_APP)/Contents/Helpers/TwinlyLauncher
	@chmod +x $(BUILD_APP)/Contents/Resources/TwinlyLauncher
	@codesign --force --deep --sign - $(BUILD_APP)
	@echo "Built $(BUILD_APP) successfully!"

dmg: app
	@echo "Packaging $(DMG_NAME)..."
	@rm -rf build/dmg_temp $(BUILD_DMG)
	@mkdir -p build/dmg_temp
	@cp -R $(BUILD_APP) build/dmg_temp/
	@ln -s /Applications build/dmg_temp/Applications
	@hdiutil create -volname "Twinly" -srcfolder build/dmg_temp -ov -format UDZO $(BUILD_DMG)
	@rm -rf build/dmg_temp
	@echo "Created $(BUILD_DMG) successfully!"

install: app
	@echo "Installing Twinly.app to /Applications..."
	@cp -R $(BUILD_APP) /Applications/
	@echo "Installed to /Applications/Twinly.app"

clean:
	rm -rf .build build
