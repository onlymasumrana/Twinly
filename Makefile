APP_NAME = Twinly.app
BUILD_APP = build/$(APP_NAME)
DMG_NAME = Twinly.dmg
BUILD_DMG = build/$(DMG_NAME)
ZIP_NAME = Twinly.zip
BUILD_ZIP = build/$(ZIP_NAME)

.PHONY: all build build-universal test app dmg zip clean install bump-patch bump-minor update-cask release

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
	swift build --product TwinlyLauncher && swift run TwinlyTestsRunner

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

zip: app
	@echo "Packaging $(ZIP_NAME)..."
	@rm -f $(BUILD_ZIP)
	@ditto -c -k --sequesterRsrc --keepParent $(BUILD_APP) $(BUILD_ZIP)
	@echo "Created $(BUILD_ZIP) successfully!"

install: app
	@echo "Installing Twinly.app to /Applications..."
	@rm -rf /Applications/$(APP_NAME)
	@cp -R $(BUILD_APP) /Applications/
	@echo "Installed to /Applications/Twinly.app"

bump-patch:
	@CUR_VER=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist); \
	CUR_BUILD=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist); \
	NEW_VER=$$(echo "$$CUR_VER" | awk -F. '{printf "%d.%d.%d", $$1, $$2, $$3+1}'); \
	NEW_BUILD=$$((CUR_BUILD + 1)); \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$NEW_VER" Resources/Info.plist; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$NEW_BUILD" Resources/Info.plist; \
	echo "Bumped version: $$CUR_VER (build $$CUR_BUILD) -> $$NEW_VER (build $$NEW_BUILD)"

bump-minor:
	@CUR_VER=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist); \
	CUR_BUILD=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist); \
	NEW_VER=$$(echo "$$CUR_VER" | awk -F. '{printf "%d.%d.0", $$1, $$2+1}'); \
	NEW_BUILD=$$((CUR_BUILD + 1)); \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$NEW_VER" Resources/Info.plist; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$NEW_BUILD" Resources/Info.plist; \
	echo "Bumped version: $$CUR_VER (build $$CUR_BUILD) -> $$NEW_VER (build $$NEW_BUILD)"

update-cask:
	@CASK_FILE="$(HOME)/Developer/homebrew-tap/Casks/twinly.rb"; \
	if [ -f "$$CASK_FILE" ] && [ -f "$(BUILD_DMG)" ]; then \
		VER=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist); \
		SHA=$$(shasum -a 256 "$(BUILD_DMG)" | awk '{print $$1}'); \
		sed -i '' -E "s/^  version \".*\"/  version \"$$VER\"/" "$$CASK_FILE"; \
		sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$$SHA\"/" "$$CASK_FILE"; \
		cd "$(HOME)/Developer/homebrew-tap" && git add Casks/twinly.rb && \
		(git diff --cached --quiet || (git commit -m "Update twinly cask to v$$VER" && git push origin main)); \
		echo "Updated Homebrew cask to v$$VER ($$SHA)"; \
	else \
		echo "Skipping update-cask: $$CASK_FILE or $(BUILD_DMG) not found"; \
	fi

release: bump-patch dmg zip
	@VER=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist); \
	git add -A && git commit -m "Release v$$VER" && git push origin main && \
	gh release create "v$$VER" $(BUILD_DMG) $(BUILD_ZIP) --title "Twinly v$$VER" --generate-notes
	@$(MAKE) update-cask

clean:
	rm -rf .build build
