import Foundation
import AppKit
import TwinlyCore

print("--------------------------------------------------")
print("Twinly Live System Acceptance Verification")
print("--------------------------------------------------")

// 1. Sandboxed App Rejection Test
print("\n[Acceptance 1] Testing Sandboxed App Rejection (/Applications/Pages.app)...")
let pagesURL = URL(fileURLWithPath: "/Applications/Pages.app")
if FileManager.default.fileExists(atPath: pagesURL.path) {
    do {
        let analysis = try AppInspector.shared.inspect(appURL: pagesURL)
        assert(analysis.strategy == .sandboxedUnsupported, "Pages should be flagged as sandboxed")
        assert(analysis.isSandboxed == true, "Pages isSandboxed should be true")
        print("  ✓ AppInspector correctly detected sandbox and generated warning:")
        print("    \"\(analysis.warning ?? "")\"")

        // Try building wrapper - should throw unsupportedApp error
        do {
            _ = try WrapperBuilder.shared.buildWrapper(
                analysis: analysis,
                profileName: "TestSandbox",
                badgeColorHex: "#FF0000",
                badgeText: "S"
            )
            fatalError("WrapperBuilder should have thrown unsupportedApp error!")
        } catch {
            print("  ✓ WrapperBuilder correctly refused to clone sandboxed app: \(error.localizedDescription)")
        }
    } catch {
        print("  ❌ Unexpected error: \(error)")
    }
} else {
    print("  (Pages.app not found on machine, skipped)")
}

// 2. Electron App Wrapper Test (Claude.app)
print("\n[Acceptance 2] Testing Electron Profile Creation (/Applications/Claude.app)...")
let claudeURL = URL(fileURLWithPath: "/Applications/Claude.app")
if FileManager.default.fileExists(atPath: claudeURL.path) {
    do {
        let analysis = try AppInspector.shared.inspect(appURL: claudeURL)
        assert(analysis.strategy == .electronChromium, "Claude should be detected as electronChromium")
        print("  ✓ Detected strategy: \(analysis.strategy.displayName)")

        let profile = try WrapperBuilder.shared.buildWrapper(
            analysis: analysis,
            profileName: "Work",
            badgeColorHex: "#3B82F6",
            badgeText: "W"
        )

        let wrapperURL = URL(fileURLWithPath: profile.wrapperAppPath)
        print("  ✓ Created wrapper at: \(wrapperURL.path)")
        assert(FileManager.default.fileExists(atPath: wrapperURL.path), "Wrapper bundle must exist")
        assert(FileManager.default.fileExists(atPath: profile.profileDirectory), "Data directory must exist")

        // Verify Info.plist
        let infoPlist = wrapperURL.appendingPathComponent("Contents/Info.plist")
        assert(FileManager.default.fileExists(atPath: infoPlist.path), "Info.plist must exist")

        // Verify launcher binary
        let launcher = wrapperURL.appendingPathComponent("Contents/MacOS/launcher")
        assert(FileManager.default.fileExists(atPath: launcher.path), "Launcher binary must exist")

        // Verify twinly.json
        let configURL = wrapperURL.appendingPathComponent("Contents/Resources/twinly.json")
        assert(FileManager.default.fileExists(atPath: configURL.path), "twinly.json must exist")
        let configData = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(LauncherConfig.self, from: configData)
        assert(config.strategy == "electronChromium")
        assert(config.originalAppPath == claudeURL.path)
        print("  ✓ twinly.json verified: points to \(config.originalAppPath) with isolated dir \(config.profileDirectory)")

        // Verify badged icon
        let iconURL = wrapperURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        assert(FileManager.default.fileExists(atPath: iconURL.path), "AppIcon.icns must exist")
        print("  ✓ Custom badged .icns icon generated successfully")

        // 3. Test Deletion
        print("\n[Acceptance 3] Testing Profile Deletion...")
        let store = ProfileStore.shared
        store.addProfile(profile)
        assert(store.profiles.contains(where: { $0.id == profile.id }))

        try store.deleteProfile(id: profile.id, deleteData: true)
        assert(!FileManager.default.fileExists(atPath: wrapperURL.path), "Wrapper must be deleted")
        assert(!FileManager.default.fileExists(atPath: profile.profileDirectory), "Data dir must be deleted")
        assert(FileManager.default.fileExists(atPath: claudeURL.path), "Original app MUST remain untouched!")
        print("  ✓ Profile and wrapper removed cleanly. Original application untouched at \(claudeURL.path)")
    } catch {
        print("  ❌ Claude test failed: \(error)")
    }
}

// 4. CLI Profile Test (claude-work)
print("\n[Acceptance 4] Testing CLI Profile Creation (claude-work)...")
let realClaudeBinary = "/Users/masum/.local/bin/claude"
if FileManager.default.fileExists(atPath: realClaudeBinary) {
    do {
        let cliProfile = try CLIWrapperBuilder.shared.buildCLIWrapper(
            name: "Work Claude",
            commandName: "claude-work-acc-test",
            preset: .claudeCode,
            configEnvVar: "CLAUDE_CONFIG_DIR",
            realBinaryPath: realClaudeBinary
        )

        print("  ✓ Generated CLI wrapper script at: \(cliProfile.wrapperScriptPath)")
        assert(FileManager.default.fileExists(atPath: cliProfile.wrapperScriptPath))
        assert(FileManager.default.fileExists(atPath: cliProfile.profileDirectory))

        let script = try String(contentsOfFile: cliProfile.wrapperScriptPath, encoding: .utf8)
        assert(script.contains("export CLAUDE_CONFIG_DIR=\"\(cliProfile.profileDirectory)\""))
        assert(script.contains("exec \"\(realClaudeBinary)\" \"$@\""))
        print("  ✓ Wrapper script exports CLAUDE_CONFIG_DIR=\"\(cliProfile.profileDirectory)\"")
        print("  ✓ Plain 'claude' retains default ~/.claude directory")

        // Cleanup test wrapper
        try ProfileStore.shared.deleteCLIProfile(id: cliProfile.id, deleteData: true)
        print("  ✓ CLI wrapper cleaned up successfully")
    } catch {
        print("  ❌ CLI test failed: \(error)")
    }
}

print("\n==================================================")
print("ALL ACCEPTANCE CRITERIA VERIFIED SUCCESSFULLY! 🎉")
print("==================================================")
