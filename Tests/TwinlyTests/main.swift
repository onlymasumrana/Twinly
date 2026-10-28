import Foundation
import AppKit
import TwinlyCore

var totalTests = 0
var passedTests = 0
var failedTests = 0

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if a == b {
        passedTests += 1
    } else {
        failedTests += 1
        print("❌ FAIL at \(URL(fileURLWithPath: file).lastPathComponent):\(line): \(a) != \(b). \(message)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if condition {
        passedTests += 1
    } else {
        failedTests += 1
        print("❌ FAIL at \(URL(fileURLWithPath: file).lastPathComponent):\(line): Expected true. \(message)")
    }
}

func assertFalse(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if !condition {
        passedTests += 1
    } else {
        failedTests += 1
        print("❌ FAIL at \(URL(fileURLWithPath: file).lastPathComponent):\(line): Expected false. \(message)")
    }
}

func assertNotNil(_ value: Any?, _ message: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if value != nil {
        passedTests += 1
    } else {
        failedTests += 1
        print("❌ FAIL at \(URL(fileURLWithPath: file).lastPathComponent):\(line): Expected non-nil. \(message)")
    }
}

func createMockAppBundle(
    in tempDir: URL,
    name: String,
    isElectron: Bool
) throws -> URL {
    let appURL = tempDir.appendingPathComponent("\(name).app")
    let contents = appURL.appendingPathComponent("Contents")
    let macos = contents.appendingPathComponent("MacOS")
    let resources = contents.appendingPathComponent("Resources")
    let frameworks = contents.appendingPathComponent("Frameworks")

    try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)

    let binaryURL = macos.appendingPathComponent(name)
    let mockScript = "#!/bin/sh\necho 'Mock App'\n"
    try mockScript.write(to: binaryURL, atomically: true, encoding: .utf8)
    var perms = try FileManager.default.attributesOfItem(atPath: binaryURL.path)
    perms[.posixPermissions] = 0o755
    try FileManager.default.setAttributes(perms, ofItemAtPath: binaryURL.path)

    let infoPlist: [String: Any] = [
        "CFBundleExecutable": name,
        "CFBundleIdentifier": "com.example.\(name.lowercased())",
        "CFBundleName": name,
        "CFBundleDisplayName": name,
        "CFBundlePackageType": "APPL"
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
    try plistData.write(to: contents.appendingPathComponent("Info.plist"))

    if isElectron {
        let electronFramework = frameworks.appendingPathComponent("Electron Framework.framework")
        try FileManager.default.createDirectory(at: electronFramework, withIntermediateDirectories: true)
    }

    return appURL
}

func runAllTests() {
    print("========================================")
    print(" Running Twinly Test Suite")
    print("========================================")

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TwinlyTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // 1. AppInspector Tests
    print("\n--- Test: AppInspector ---")
    do {
        let mockElectron = try createMockAppBundle(in: tempDir, name: "TestElectron", isElectron: true)
        let elAnalysis = try AppInspector.shared.inspect(appURL: mockElectron)
        assertEqual(elAnalysis.appName, "TestElectron", "AppName should match")
        assertEqual(elAnalysis.strategy, .electronChromium, "Strategy should be electronChromium")
        assertFalse(elAnalysis.isSandboxed, "Mock electron should not be sandboxed")
        assertTrue(elAnalysis.explanation.contains("Electron / Chromium"), "Explanation should mention Electron")

        let mockGeneric = try createMockAppBundle(in: tempDir, name: "TestGeneric", isElectron: false)
        let genAnalysis = try AppInspector.shared.inspect(appURL: mockGeneric)
        assertEqual(genAnalysis.appName, "TestGeneric", "AppName should match")
        assertEqual(genAnalysis.strategy, .genericNonSandboxed, "Strategy should be genericNonSandboxed")
        assertFalse(genAnalysis.isSandboxed, "Mock generic should not be sandboxed")
        assertTrue(genAnalysis.explanation.contains("generic non-sandboxed"), "Explanation should mention generic non-sandboxed")
    } catch {
        failedTests += 1
        print("❌ AppInspector mock test failed with error: \(error)")
    }

    // Real system apps
    print("\n--- Test: Real System Apps Inspection ---")
    let pagesURL = URL(fileURLWithPath: "/Applications/Pages.app")
    if FileManager.default.fileExists(atPath: pagesURL.path) {
        do {
            let pagesAnalysis = try AppInspector.shared.inspect(appURL: pagesURL)
            assertEqual(pagesAnalysis.strategy, .sandboxedUnsupported, "Pages.app should be sandboxedUnsupported")
            assertTrue(pagesAnalysis.isSandboxed, "Pages.app should be sandboxed")
            assertNotNil(pagesAnalysis.warning, "Pages.app should provide warning")
            print("  ✓ Pages.app correctly identified as sandboxed/unsupported")
        } catch {
            failedTests += 1
            print("❌ Pages.app inspection failed: \(error)")
        }
    }

    let claudeURL = URL(fileURLWithPath: "/Applications/Claude.app")
    if FileManager.default.fileExists(atPath: claudeURL.path) {
        do {
            let claudeAnalysis = try AppInspector.shared.inspect(appURL: claudeURL)
            assertEqual(claudeAnalysis.strategy, .electronChromium, "Claude.app should be electronChromium")
            assertFalse(claudeAnalysis.isSandboxed, "Claude.app should not be sandboxed")
            print("  ✓ Claude.app correctly identified as Electron")
        } catch {
            failedTests += 1
            print("❌ Claude.app inspection failed: \(error)")
        }
    }

    let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    if FileManager.default.fileExists(atPath: chromeURL.path) {
        do {
            let chromeAnalysis = try AppInspector.shared.inspect(appURL: chromeURL)
            assertEqual(chromeAnalysis.strategy, .electronChromium, "Google Chrome should be electronChromium")
            assertFalse(chromeAnalysis.isSandboxed, "Google Chrome should not be sandboxed")
            print("  ✓ Google Chrome correctly identified as Chromium")
        } catch {
            failedTests += 1
            print("❌ Google Chrome inspection failed: \(error)")
        }
    }

    // 2. CLIWrapperBuilder Tests
    print("\n--- Test: CLIWrapperBuilder ---")
    do {
        let binDir = tempDir.appendingPathComponent("bin")
        let cliDataDir = tempDir.appendingPathComponent("cli_profiles")

        let cliProfile = try CLIWrapperBuilder.shared.buildCLIWrapper(
            name: "Work Claude",
            commandName: "claude-work-test",
            preset: .claudeCode,
            configEnvVar: "CLAUDE_CONFIG_DIR",
            realBinaryPath: "/usr/bin/true",
            customEnv: ["MY_VAR": "TEST_VAL"],
            customBinDir: binDir,
            customCLIProfilesDir: cliDataDir
        )

        assertEqual(cliProfile.commandName, "claude-work-test")
        assertEqual(cliProfile.configEnvVar, "CLAUDE_CONFIG_DIR")
        assertTrue(FileManager.default.fileExists(atPath: cliProfile.wrapperScriptPath), "Wrapper script should exist")
        assertTrue(FileManager.default.fileExists(atPath: cliProfile.profileDirectory), "Profile directory should exist")

        let script = try String(contentsOfFile: cliProfile.wrapperScriptPath, encoding: .utf8)
        assertTrue(script.contains("export CLAUDE_CONFIG_DIR=\"\(cliProfile.profileDirectory)\""), "Script should export config dir")
        assertTrue(script.contains("export MY_VAR=\"TEST_VAL\""), "Script should export custom env")
        assertTrue(script.contains("exec \"/usr/bin/true\" \"$@\""), "Script should exec real binary")

        let perms = try FileManager.default.attributesOfItem(atPath: cliProfile.wrapperScriptPath)
        let posix = (perms[.posixPermissions] as? NSNumber)?.intValue ?? 0
        assertEqual(posix & 0o111, 0o111, "Wrapper script should be executable")

        let fixCmd = CLIWrapperBuilder.shared.shellPathFixCommand()
        assertTrue(fixCmd.contains(".local/bin"), "Path fix command should contain .local/bin")
    } catch {
        failedTests += 1
        print("❌ CLIWrapperBuilder test failed: \(error)")
    }

    // 3. IconBadgeGenerator Tests
    print("\n--- Test: IconBadgeGenerator ---")
    do {
        let baseImg = NSImage(size: NSSize(width: 128, height: 128))
        baseImg.lockFocus()
        NSColor.gray.setFill()
        NSRect(x: 0, y: 0, width: 128, height: 128).fill()
        baseImg.unlockFocus()

        let badged = IconBadgeGenerator.shared.createBadgedImage(
            baseImage: baseImg,
            badgeColor: .systemBlue,
            badgeText: "W",
            targetSize: CGSize(width: 128, height: 128)
        )
        assertEqual(badged.size.width, 128)

        let icnsURL = tempDir.appendingPathComponent("test.icns")
        try IconBadgeGenerator.shared.generateIcns(
            baseImage: baseImg,
            badgeColor: .systemRed,
            badgeText: "2",
            destinationURL: icnsURL
        )
        assertTrue(FileManager.default.fileExists(atPath: icnsURL.path), "ICNS file should be created")
        let icnsData = try Data(contentsOf: icnsURL)
        assertTrue(icnsData.count > 100, "ICNS data should not be empty")
    } catch {
        failedTests += 1
        print("❌ IconBadgeGenerator test failed: \(error)")
    }

    // 4. LauncherConfig Tests
    print("\n--- Test: LauncherConfig ---")
    do {
        let profileId = UUID()
        let config = LauncherConfig(
            version: 1,
            profileId: profileId,
            profileName: "Secondary",
            originalAppPath: "/Applications/Claude.app",
            executablePath: "/Applications/Claude.app/Contents/MacOS/Claude",
            strategy: "electronChromium",
            profileDirectory: "/tmp/data",
            arguments: ["--flag1", "--flag2"],
            environment: ["A": "1"]
        )

        let enc = try JSONEncoder().encode(config)
        let dec = try JSONDecoder().decode(LauncherConfig.self, from: enc)

        assertEqual(dec.profileId, profileId)
        assertEqual(dec.profileName, "Secondary")
        assertEqual(dec.strategy, "electronChromium")
        assertEqual(dec.arguments, ["--flag1", "--flag2"])
        assertEqual(dec.environment["A"], "1")
    } catch {
        failedTests += 1
        print("❌ LauncherConfig test failed: \(error)")
    }

    // 5. WrapperBuilder Full Build Test
    print("\n--- Test: WrapperBuilder ---")
    do {
        let mockApp = try createMockAppBundle(in: tempDir, name: "SampleApp", isElectron: true)
        let analysis = try AppInspector.shared.inspect(appURL: mockApp)

        let customTargetDir = tempDir.appendingPathComponent("Applications")
        let customDataDir = tempDir.appendingPathComponent("ProfilesData")

        let profile = try WrapperBuilder.shared.buildWrapper(
            analysis: analysis,
            profileName: "Work",
            badgeColorHex: "#EF4444",
            badgeText: "W",
            customArgs: ["--custom-arg"],
            customEnv: ["CUSTOM_ENV": "1"],
            customTargetDir: customTargetDir,
            customProfilesDataDir: customDataDir
        )

        assertEqual(profile.name, "Work")
        assertEqual(profile.appName, "SampleApp")
        assertTrue(FileManager.default.fileExists(atPath: profile.wrapperAppPath), "Wrapper bundle should exist")

        let wrapperURL = URL(fileURLWithPath: profile.wrapperAppPath)
        let infoPlistURL = wrapperURL.appendingPathComponent("Contents/Info.plist")
        assertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path), "Info.plist should exist")

        let launcherBinaryURL = wrapperURL.appendingPathComponent("Contents/MacOS/launcher")
        assertTrue(FileManager.default.fileExists(atPath: launcherBinaryURL.path), "Launcher binary should exist")

        let twinlyJsonURL = wrapperURL.appendingPathComponent("Contents/Resources/twinly.json")
        assertTrue(FileManager.default.fileExists(atPath: twinlyJsonURL.path), "twinly.json should exist")

        let iconURL = wrapperURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        assertTrue(FileManager.default.fileExists(atPath: iconURL.path), "AppIcon.icns should exist")

        // Validate twinly.json contents
        let jsonData = try Data(contentsOf: twinlyJsonURL)
        let decodedConfig = try JSONDecoder().decode(LauncherConfig.self, from: jsonData)
        assertEqual(decodedConfig.profileName, "Work")
        assertEqual(decodedConfig.strategy, "electronChromium")
        assertEqual(decodedConfig.arguments, ["--custom-arg"])
        assertEqual(decodedConfig.environment["CUSTOM_ENV"], "1")

        // Validate Info.plist
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        assertEqual(plist?["CFBundleExecutable"] as? String, "launcher")
        assertTrue((plist?["CFBundleIdentifier"] as? String)?.contains("io.twinly") == true)
    } catch {
        failedTests += 1
        print("❌ WrapperBuilder test failed: \(error)")
    }

    // 6. ProfileStore Lifecycle Tests
    print("\n--- Test: ProfileStore Lifecycle ---")
    do {
        let storeDir = tempDir.appendingPathComponent("store")
        let store = ProfileStore(baseStorageDir: storeDir)

        let p1 = Profile(
            name: "Work Discord",
            originalAppPath: "/Applications/Discord.app",
            originalBundleId: "com.hnc.Discord",
            appName: "Discord",
            strategy: .electronChromium,
            profileDirectory: tempDir.appendingPathComponent("discord_data").path,
            wrapperAppPath: tempDir.appendingPathComponent("Discord (Work).app").path
        )

        store.addProfile(p1)
        assertEqual(store.profiles.count, 1)

        // Modify & Update
        var updated = p1
        updated.name = "Work Discord Updated"
        store.updateProfile(updated)
        assertEqual(store.profiles.first?.name, "Work Discord Updated")

        // Re-read store from disk
        let storeFresh = ProfileStore(baseStorageDir: storeDir)
        assertEqual(storeFresh.profiles.count, 1)
        assertEqual(storeFresh.profiles.first?.name, "Work Discord Updated")

        // Delete without deleting data
        try storeFresh.deleteProfile(id: p1.id, deleteData: false)
        assertEqual(storeFresh.profiles.count, 0)
    } catch {
        failedTests += 1
        print("❌ ProfileStore test failed: \(error)")
    }

    // Summary
    print("\n========================================")
    print(" Test Run Complete")
    print(" Total assertions: \(totalTests)")
    print(" Passed:           \(passedTests)")
    print(" Failed:           \(failedTests)")
    print("========================================")

    if failedTests > 0 {
        exit(1)
    } else {
        exit(0)
    }
}

runAllTests()
