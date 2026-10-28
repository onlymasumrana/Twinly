APP_NAME = Twinly.app
BUILD_APP = build/$(APP_NAME)
DMG_NAME = Twinly.dmg
BUILD_DMG = build/$(DMG_NAME)

.PHONY: all build build-universal test app dmg clean install

all: build-universal

build:
	swift build -c release

build-universal:
	@echo "Building for Apple Silicon (arm64)..."
	swift build -c release --triple arm64-apple-macosx13.0
	@echo "Building for Intel (x86_64)..."
	swift build -c release --triple x86_64-apple-macosx13.0
	@mkdir -p .build/universal
	@lipo -create .build/arm64-apple-macosx/release/Twinly .build/x86_64-apple-macosx/release/Twinly -output .build/universal/Twinly
	@lipo -create .build/arm64-apple-macosx/release/TwinlyLauncher .build/x86_64-apple-macosx/release/TwinlyLauncher -output .build/universal/TwinlyLauncher
	@echo "Created universal binaries successfully!"

test:
	swift run TwinlyTestsRunner

app: build-universal
	@echo "Creating $(APP_NAME)..."
	@rm -rf $(BUILD_APP)
	@mkdir -p $(BUILD_APP)/Contents/MacOS
	@mkdir -p $(BUILD_APP)/Contents/Resources
	@mkdir -p $(BUILD_APP)/Contents/Helpers
	@cp .build/universal/Twinly $(BUILD_APP)/Contents/MacOS/Twinly
	@cp .build/universal/TwinlyLauncher $(BUILD_APP)/Contents/Helpers/TwinlyLauncher
	@cp .build/universal/TwinlyLauncher $(BUILD_APP)/Contents/Resources/TwinlyLauncher
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
