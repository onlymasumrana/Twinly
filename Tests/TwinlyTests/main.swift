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
        assertTrue(script.contains("export CLAUDE_CONFIG_DIR='\(cliProfile.profileDirectory)'"), "Script should export config dir")
        assertTrue(script.contains("export MY_VAR='TEST_VAL'"), "Script should export custom env")
        assertTrue(script.contains("exec '/usr/bin/true' \"$@\""), "Script should exec real binary")
        assertTrue(script.contains("# twinly-cli-profile"), "Script should carry the Twinly marker")

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

    // 7. Edit keeps data
    print("\n--- Test: Edit keeps data ---")
    do {
        let app = try createMockAppBundle(in: tempDir, name: "EditApp", isElectron: true)
        let analysis = try AppInspector.shared.inspect(appURL: app)
        let apps = tempDir.appendingPathComponent("EditApps")
        let data = tempDir.appendingPathComponent("EditData")
        let p1 = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "Work", badgeColorHex: "#EF4444", badgeText: "W", customTargetDir: apps, customProfilesDataDir: data)
        let marker = URL(fileURLWithPath: p1.profileDirectory).appendingPathComponent("login.txt")
        try "secret".write(to: marker, atomically: true, encoding: .utf8)
        let p2 = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "Personal", badgeColorHex: "#3B82F6", badgeText: "P", customTargetDir: apps, customProfilesDataDir: data, existing: p1)
        assertEqual(p2.id, p1.id)
        assertEqual(p2.profileDirectory, p1.profileDirectory)
        assertEqual(p2.createdAt, p1.createdAt)
        assertTrue(FileManager.default.fileExists(atPath: marker.path), "Data file should survive edit")
        assertTrue(FileManager.default.fileExists(atPath: p2.wrapperAppPath), "New app should exist")
        assertFalse(FileManager.default.fileExists(atPath: p1.wrapperAppPath), "Old app should be removed")
        let json = try Data(contentsOf: URL(fileURLWithPath: p2.wrapperAppPath).appendingPathComponent("Contents/Resources/twinly.json"))
        let cfg = try JSONDecoder().decode(LauncherConfig.self, from: json)
        assertEqual(cfg.profileDirectory, p1.profileDirectory)
        assertEqual(cfg.profileId, p1.id)
    } catch {
        failedTests += 1
        print("❌ Edit keeps data test failed: \(error)")
    }

    // 8. Repair keeps data
    print("\n--- Test: Repair keeps data ---")
    do {
        let app = try createMockAppBundle(in: tempDir, name: "RepairApp", isElectron: false)
        let analysis = try AppInspector.shared.inspect(appURL: app)
        let apps = tempDir.appendingPathComponent("RepairApps")
        let data = tempDir.appendingPathComponent("RepairData")
        let p = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "Work", badgeColorHex: "#EF4444", badgeText: "W", customTargetDir: apps, customProfilesDataDir: data)
        let store = ProfileStore(baseStorageDir: tempDir.appendingPathComponent("RepairStore"))
        store.addProfile(p)
        let result = store.rebuildAllWrappers(targetDir: apps, dataDir: data)
        assertEqual(result.repaired.count, 1, "failed: \(result.failed)")
        assertEqual(result.failed.count, 0)
        assertEqual(store.profiles.first?.profileDirectory, p.profileDirectory)
        assertEqual(store.profiles.first?.id, p.id)
        assertEqual(store.profiles.first?.createdAt, p.createdAt)
    } catch {
        failedTests += 1
        print("❌ Repair keeps data test failed: \(error)")
    }

    // 9. Name conflict
    print("\n--- Test: Name conflict ---")
    do {
        let app = try createMockAppBundle(in: tempDir, name: "ConflictApp", isElectron: true)
        let analysis = try AppInspector.shared.inspect(appURL: app)
        let apps = tempDir.appendingPathComponent("ConflictApps")
        let data = tempDir.appendingPathComponent("ConflictData")
        _ = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "Work", badgeColorHex: "#EF4444", badgeText: "W", customTargetDir: apps, customProfilesDataDir: data)
        var threw = false
        do {
            _ = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "Work", badgeColorHex: "#EF4444", badgeText: "W", customTargetDir: apps, customProfilesDataDir: data)
        } catch WrapperBuilderError.nameConflict {
            threw = true
        }
        assertTrue(threw, "Second profile with same name should throw nameConflict")
        // "a/b" and "a:b" collapse to the same file name
        _ = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "a/b", badgeColorHex: "#EF4444", badgeText: "W", customTargetDir: apps, customProfilesDataDir: data)
        var threw2 = false
        do {
            _ = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "a:b", badgeColorHex: "#EF4444", badgeText: "W", customTargetDir: apps, customProfilesDataDir: data)
        } catch WrapperBuilderError.nameConflict {
            threw2 = true
        }
        assertTrue(threw2, "Names that sanitize identically should conflict")
    } catch {
        failedTests += 1
        print("❌ Name conflict test failed: \(error)")
    }

    // 10. Bundle id
    print("\n--- Test: Bundle id ---")
    do {
        let app = try createMockAppBundle(in: tempDir, name: "EmojiApp", isElectron: true)
        let analysis = try AppInspector.shared.inspect(appURL: app)
        let p = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "🔥", badgeColorHex: "#EF4444", badgeText: "🔥", customTargetDir: tempDir.appendingPathComponent("EmojiApps"), customProfilesDataDir: tempDir.appendingPathComponent("EmojiData"))
        let plistData = try Data(contentsOf: URL(fileURLWithPath: p.wrapperAppPath).appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        let bid = plist?["CFBundleIdentifier"] as? String ?? ""
        assertFalse(bid.isEmpty || bid.hasSuffix("."), "Bundle id should not end in a dot: \(bid)")
    } catch {
        failedTests += 1
        print("❌ Bundle id test failed: \(error)")
    }

    // 11. Escaping
    print("\n--- Test: CLI script escaping ---")
    do {
        let binDir = tempDir.appendingPathComponent("esc_bin")
        let value = "a \"b\" $HOME `x` 'c'"
        let p = try CLIWrapperBuilder.shared.buildCLIWrapper(
            name: "Esc", commandName: "esc-test", preset: .custom, configEnvVar: "CONFIG_DIR",
            realBinaryPath: "/usr/bin/env", customEnv: ["MY_VAR": value],
            customBinDir: binDir, customCLIProfilesDir: tempDir.appendingPathComponent("esc_data")
        )
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: p.wrapperScriptPath)
        proc.standardOutput = pipe
        try proc.run()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()
        assertTrue(out.contains("MY_VAR=\(value)"), "Escaped value should round-trip literally")
    } catch {
        failedTests += 1
        print("❌ Escaping test failed: \(error)")
    }

    // 12. Validation
    print("\n--- Test: CLI validation ---")
    do {
        let binDir = tempDir.appendingPathComponent("val_bin")
        let dataDir = tempDir.appendingPathComponent("val_data")
        func throwsFor(command: String, env: [String: String] = [:], envVar: String = "CONFIG_DIR") -> Bool {
            do {
                _ = try CLIWrapperBuilder.shared.buildCLIWrapper(name: "V", commandName: command, preset: .custom, configEnvVar: envVar, realBinaryPath: "/usr/bin/true", customEnv: env, customBinDir: binDir, customCLIProfilesDir: dataDir)
                return false
            } catch { return true }
        }
        assertTrue(throwsFor(command: "a/b"), "slash")
        assertTrue(throwsFor(command: "-x"), "leading dash")
        assertTrue(throwsFor(command: ""), "empty")
        assertTrue(throwsFor(command: "ok", env: ["1BAD": "x"]), "bad env key")
        assertTrue(throwsFor(command: "ok", envVar: "1BAD"), "bad config var")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try "#!/bin/sh\necho real\n".write(to: binDir.appendingPathComponent("claude"), atomically: true, encoding: .utf8)
        assertTrue(throwsFor(command: "claude"), "must not clobber a non-Twinly file")
        let content = try String(contentsOf: binDir.appendingPathComponent("claude"), encoding: .utf8)
        assertEqual(content, "#!/bin/sh\necho real\n", "non-Twinly file untouched")
        assertFalse(throwsFor(command: "claude-ok"), "valid command should work")
    } catch {
        failedTests += 1
        print("❌ Validation test failed: \(error)")
    }

    // 13. Tokenizer
    print("\n--- Test: Argument tokenizer ---")
    let toks = InputParsing.tokenizeArguments("--a \"b c\" 'd e' f\\ g")
    assertEqual(toks, ["--a", "b c", "d e", "f g"])
    assertEqual(InputParsing.tokenizeArguments(InputParsing.formatArguments(toks)), toks, "round trip")
    assertEqual(InputParsing.tokenizeArguments("  "), [])

    // 14. Env parser
    print("\n--- Test: Env parser ---")
    if case .success(let env) = InputParsing.parseEnvironment("A=1\n\n# c\nB=x=y") {
        assertEqual(env, ["A": "1", "B": "x=y"])
    } else {
        failedTests += 1
        print("❌ Env parser should succeed")
    }
    if case .failure(let err) = InputParsing.parseEnvironment("NOEQ") {
        assertEqual(err.line, 1)
    } else {
        failedTests += 1
        print("❌ Env parser should fail for NOEQ")
    }
    if case .failure(let err) = InputParsing.parseEnvironment("A=1\n1ABC=2") {
        assertEqual(err.line, 2)
    } else {
        failedTests += 1
        print("❌ Env parser should fail for invalid name")
    }

    // 15. Corrupt store
    print("\n--- Test: Corrupt store ---")
    do {
        let dir = tempDir.appendingPathComponent("corrupt_store")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{".write(to: dir.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)
        let store = ProfileStore(baseStorageDir: dir)
        assertNotNil(store.loadError, "loadError should be set")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        assertTrue(names.contains { $0.hasPrefix("profiles.json.broken-") }, "backup should exist")
        assertEqual(try String(contentsOf: dir.appendingPathComponent("profiles.json"), encoding: .utf8), "{")
        assertEqual(store.profiles.count, 0)
    } catch {
        failedTests += 1
        print("❌ Corrupt store test failed: \(error)")
    }

    // 16. Running detector
    print("\n--- Test: Running detector ---")
    do {
        let dir = tempDir.appendingPathComponent("running")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        assertFalse(ProfileStatus.isRunning(profileDirectory: dir.path), "no lock")
        let lock = dir.appendingPathComponent("SingletonLock")
        try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "host-\(getpid())")
        assertTrue(ProfileStatus.isRunning(profileDirectory: dir.path), "live pid")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "host-999999")
        assertFalse(ProfileStatus.isRunning(profileDirectory: dir.path), "dead pid")
    } catch {
        failedTests += 1
        print("❌ Running detector test failed: \(error)")
    }

    // 17. Firefox / Gecko, Separate Dock Icon, Reset Data
    print("\n--- Test: Gecko / Separate Dock Icon / Reset ---")
    do {
        let ff = try createMockAppBundle(in: tempDir, name: "FoxLike", isElectron: false)
        try Data().write(to: ff.appendingPathComponent("Contents/Resources/omni.ja"))
        let ffAnalysis = try AppInspector.shared.inspect(appURL: ff)
        assertEqual(ffAnalysis.strategy, .firefoxGecko, "omni.ja => firefoxGecko")
        assertEqual(AppStrategy.firefoxGecko.displayName, "Firefox-based")

        let mock = try createMockAppBundle(in: tempDir, name: "CloneMe", isElectron: true)
        let plistURL = mock.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
        plist["CFBundleIconName"] = "AppIcon"
        plist["ElectronAsarIntegrity"] = ["x": "y"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        let analysis = try AppInspector.shared.inspect(appURL: mock)
        let apps = tempDir.appendingPathComponent("cloneApps")
        let data = tempDir.appendingPathComponent("cloneData")
        let profile = try WrapperBuilder.shared.buildWrapper(analysis: analysis, profileName: "Work", badgeColorHex: "#EF4444", badgeText: "W", customTargetDir: apps, customProfilesDataDir: data, separateDockIcon: true)
        let wrapper = URL(fileURLWithPath: profile.wrapperAppPath)
        let macos = wrapper.appendingPathComponent("Contents/MacOS")
        assertTrue(FileManager.default.fileExists(atPath: macos.appendingPathComponent("CloneMe.twinly-orig").path), "orig renamed")
        let launcherSize = (try? FileManager.default.attributesOfItem(atPath: macos.appendingPathComponent("CloneMe").path)[.size] as? Int) ?? 0
        let origSize = (try? FileManager.default.attributesOfItem(atPath: macos.appendingPathComponent("CloneMe.twinly-orig").path)[.size] as? Int) ?? 0
        assertTrue(launcherSize != origSize && launcherSize > 1000, "exec is launcher")
        let newPlist = try PropertyListSerialization.propertyList(from: Data(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
        assertTrue(newPlist["CFBundleIconName"] == nil, "icon name removed")
        assertEqual(newPlist["CFBundleDisplayName"] as? String, "CloneMe (Work)")
        assertEqual(newPlist["CFBundleIconFile"] as? String, "AppIcon")
        assertNotNil(newPlist["ElectronAsarIntegrity"], "original keys kept")
        assertEqual(newPlist["TwinlyProfileId"] as? String, profile.id.uuidString)
        let cfg = try JSONDecoder().decode(LauncherConfig.self, from: Data(contentsOf: wrapper.appendingPathComponent("Contents/Resources/twinly.json")))
        assertEqual(cfg.separateDockIcon, true)
        assertEqual(profile.separateDockIcon, true)

        // Reset data
        let store = ProfileStore(baseStorageDir: tempDir.appendingPathComponent("resetStore"))
        store.addProfile(profile)
        let junk = URL(fileURLWithPath: profile.profileDirectory).appendingPathComponent("Cookies")
        try "secret".write(to: junk, atomically: true, encoding: .utf8)
        try store.resetProfileData(id: profile.id)
        assertFalse(FileManager.default.fileExists(atPath: junk.path), "data wiped")
        var isDir: ObjCBool = false
        assertTrue(FileManager.default.fileExists(atPath: profile.profileDirectory, isDirectory: &isDir) && isDir.boolValue, "dir recreated")
        assertTrue(FileManager.default.fileExists(atPath: wrapper.path), "wrapper kept")
        assertFalse(store.stopProfile(profile), "nothing to stop")
    } catch {
        failedTests += 1
        print("❌ Gecko/clone/reset test failed: \(error)")
    }

    print("\n--- Test: Original app updates preserve clone data ---")
    do {
        let fm = FileManager.default
        let original = try createMockAppBundle(in: tempDir, name: "UpdatingApp", isElectron: true)
        let plistURL = original.appendingPathComponent("Contents/Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
        info["CFBundleShortVersionString"] = "1.0"
        info["CFBundleVersion"] = "1.0"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plistURL)
        let analysis = try AppInspector.shared.inspect(appURL: original)
        let builder = WrapperBuilder.shared
        let profile = try builder.buildWrapper(
            analysis: analysis, profileName: "Work", badgeColorHex: "#EF4444", badgeText: "W",
            customArgs: ["--test"], customEnv: ["TEST": "value"],
            customTargetDir: tempDir.appendingPathComponent("updateApps"),
            customProfilesDataDir: tempDir.appendingPathComponent("updateData"), separateDockIcon: true)
        assertFalse(builder.needsSyncWithOriginalApp(profile: profile))
        let dataDir = URL(fileURLWithPath: profile.profileDirectory)
        let cookies = dataDir.appendingPathComponent("Cookies")
        try "saved login".write(to: cookies, atomically: true, encoding: .utf8)
        info["CFBundleVersion"] = "2.0"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plistURL)
        let newBinary = "#!/bin/sh\necho '2.0'\n"
        try newBinary.write(to: original.appendingPathComponent("Contents/MacOS/UpdatingApp"), atomically: true, encoding: .utf8)
        assertTrue(builder.needsSyncWithOriginalApp(profile: profile))
        let marker = dataDir.appendingPathComponent(".needs_rebuild")
        try Data().write(to: marker)
        let rebuilt = try builder.buildWrapper(
            analysis: try AppInspector.shared.inspect(appURL: original), profileName: profile.name,
            badgeColorHex: profile.badgeColorHex, badgeText: profile.badgeText,
            customArgs: profile.customArgs, customEnv: profile.customEnv, existing: profile)
        assertFalse(builder.needsSyncWithOriginalApp(profile: rebuilt))
        assertEqual(rebuilt, profile, "identity, data path, wrapper path and settings survive")
        assertEqual(try String(contentsOf: cookies, encoding: .utf8), "saved login")
        assertEqual(try String(contentsOf: URL(fileURLWithPath: rebuilt.wrapperAppPath)
            .appendingPathComponent("Contents/MacOS/UpdatingApp.twinly-orig"), encoding: .utf8), newBinary)
        assertFalse(fm.fileExists(atPath: marker.path), "successful rebuild clears marker")
        try Data().write(to: marker)
        assertTrue(builder.needsSyncWithOriginalApp(profile: rebuilt), "marker alone requests rebuild")
        try fm.removeItem(at: marker)
        let wrapperPlist = URL(fileURLWithPath: rebuilt.wrapperAppPath).appendingPathComponent("Contents/Info.plist")
        var stamped = try PropertyListSerialization.propertyList(from: Data(contentsOf: wrapperPlist), format: nil) as! [String: Any]
        assertEqual(stamped["TwinlyOriginalBundleVersion"] as? String, "2.0")
        assertEqual(stamped["TwinlyOriginalShortVersion"] as? String, "1.0")
        stamped.removeValue(forKey: "TwinlyOriginalBundleVersion")
        try PropertyListSerialization.data(fromPropertyList: stamped, format: .xml, options: 0).write(to: wrapperPlist)
        assertTrue(builder.needsSyncWithOriginalApp(profile: rebuilt), "unstamped old clones are refreshed")
        var lightweight = rebuilt
        lightweight.separateDockIcon = nil
        assertFalse(builder.needsSyncWithOriginalApp(profile: lightweight))
        try fm.removeItem(at: original)
        assertFalse(builder.needsSyncWithOriginalApp(profile: rebuilt), "missing originals are skipped")

        let unversioned = try createMockAppBundle(in: tempDir, name: "Unversioned", isElectron: true)
        let first = OriginalAppVersion(appURL: unversioned)
        let executable = unversioned.appendingPathComponent("Contents/MacOS/Unversioned")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 123456789)], ofItemAtPath: executable.path)
        assertFalse(OriginalAppVersion(appURL: unversioned).matches(stampedInfo: [
            "TwinlyOriginalShortVersion": first.shortVersion, "TwinlyOriginalBundleVersion": first.bundleVersion
        ]), "unversioned executable changes use modification date")
    } catch {
        failedTests += 1
        print("❌ Clone update test failed: \(error)")
    }

    print("\n--- Test: Legacy v1.0.0 JSON ---")
    do {
        let id = UUID()
        let profileJSON = """
        [{"id":"\(id.uuidString)","name":"Work","originalAppPath":"/Applications/Claude.app",
          "originalBundleId":"com.example.claude","appName":"Claude","strategy":"electronChromium",
          "badgeColorHex":"#EF4444","badgeText":"W","profileDirectory":"/profiles/work",
          "wrapperAppPath":"/apps/Claude (Work).app","customArgs":["--test"],"customEnv":{"TEST":"yes"},
          "createdAt":42,"lastLaunchedAt":84}]
        """
        let decoder = JSONDecoder()
        let expected = Profile(id: id, name: "Work", originalAppPath: "/Applications/Claude.app",
            originalBundleId: "com.example.claude", appName: "Claude", strategy: .electronChromium,
            badgeColorHex: "#EF4444", badgeText: "W", profileDirectory: "/profiles/work",
            wrapperAppPath: "/apps/Claude (Work).app", customArgs: ["--test"], customEnv: ["TEST": "yes"],
            createdAt: Date(timeIntervalSinceReferenceDate: 42), lastLaunchedAt: Date(timeIntervalSinceReferenceDate: 84))
        assertEqual(try decoder.decode([Profile].self, from: Data(profileJSON.utf8)), [expected])
        let configJSON = """
        [{"version":1,"profileId":"\(id.uuidString)","profileName":"Work",
          "originalAppPath":"/Applications/Claude.app","executablePath":"/Applications/Claude.app/Contents/MacOS/Claude",
          "strategy":"electronChromium","profileDirectory":"/profiles/work",
          "arguments":["--test"],"environment":{"TEST":"yes"}}]
        """
        let configs = try decoder.decode([LauncherConfig].self, from: Data(configJSON.utf8))
        assertEqual(configs.count, 1)
        let config = configs[0]
        assertEqual(config.version, 1)
        assertEqual(config.profileId, id)
        assertEqual(config.profileName, "Work")
        assertEqual(config.originalAppPath, expected.originalAppPath)
        assertEqual(config.executablePath, "/Applications/Claude.app/Contents/MacOS/Claude")
        assertEqual(config.strategy, expected.strategy.rawValue)
        assertEqual(config.profileDirectory, expected.profileDirectory)
        assertEqual(config.arguments, expected.customArgs)
        assertEqual(config.environment, expected.customEnv)
        assertEqual(config.separateDockIcon, nil)
        let storeDir = tempDir.appendingPathComponent("legacyStore")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        try Data(profileJSON.utf8).write(to: storeDir.appendingPathComponent("profiles.json"))
        let cli = CLIProfile(id: id, name: "CLI", commandName: "claude-work", preset: .claudeCode,
            configEnvVar: "CLAUDE_CONFIG_DIR", profileDirectory: "/cli/work", realBinaryPath: "/bin/claude",
            wrapperScriptPath: "/bin/claude-work")
        var cliJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cli)) as! [String: Any]
        cliJSON.removeValue(forKey: "customEnv")
        cliJSON.removeValue(forKey: "createdAt")
        try JSONSerialization.data(withJSONObject: [cliJSON]).write(to: storeDir.appendingPathComponent("cli_profiles.json"))
        let store = ProfileStore(baseStorageDir: storeDir)
        assertEqual(store.loadError, nil)
        assertEqual(store.profiles, [expected])
        assertEqual(store.cliProfiles.first?.id, id)
        assertEqual(store.cliProfiles.first?.customEnv, [:])
        // Missing newly introduced collections must also use their defaults.
        var minimal = try JSONSerialization.jsonObject(with: Data(profileJSON.utf8)) as! [[String: Any]]
        for key in ["customArgs", "customEnv", "createdAt", "lastLaunchedAt", "badgeText", "badgeColorHex"] {
            minimal[0].removeValue(forKey: key)
        }
        let old = try decoder.decode([Profile].self, from: JSONSerialization.data(withJSONObject: minimal))[0]
        assertEqual(old.id, id)
        assertEqual(old.profileDirectory, expected.profileDirectory)
        assertEqual(old.customArgs, [])
        assertEqual(old.customEnv, [:])
        var minimalConfig = try JSONSerialization.jsonObject(with: Data(configJSON.utf8)) as! [[String: Any]]
        for key in ["version", "arguments", "environment"] { minimalConfig[0].removeValue(forKey: key) }
        let oldConfig = try decoder.decode([LauncherConfig].self, from: JSONSerialization.data(withJSONObject: minimalConfig))[0]
        assertEqual(oldConfig.version, 1)
        assertEqual(oldConfig.arguments, [])
        assertEqual(oldConfig.environment, [:])
    } catch {
        failedTests += 1
        print("❌ Legacy JSON test failed: \(error)")
    }

    // UpdateChecker
    assertEqual(UpdateChecker.normalizeVersion("v1.2.0"), [1, 2, 0])
    assertEqual(UpdateChecker.normalizeVersion("V2.0-3"), [2, 0, 3])
    assertTrue(UpdateChecker.isNewerVersion(remote: "v1.1.0", current: "1.0.0"))
    assertFalse(UpdateChecker.isNewerVersion(remote: "1.0.0", current: "v1.0.0"))
    assertTrue(UpdateChecker.isNewerVersion(remote: "2.0", current: "1.9.9"))
    assertTrue(UpdateChecker.isNewerVersion(remote: "1.0.1", current: "1.0.0"))
    assertFalse(UpdateChecker.isNewerVersion(remote: "1.0.0", current: "1.0.1"))
    do {
        let json = """
        {"tag_name":"v1.3.0","name":"Twinly 1.3.0","body":"Notes","html_url":"https://github.com/onlymasumrana/Twinly/releases/tag/v1.3.0",
         "published_at":"2026-01-01T00:00:00Z",
         "assets":[{"name":"Twinly.dmg","browser_download_url":"https://x/Twinly.dmg"},{"name":"Twinly.zip","browser_download_url":"https://x/Twinly.zip"}]}
        """
        let info = try UpdateChecker.parseRelease(from: Data(json.utf8))
        assertEqual(info.tagName, "v1.3.0")
        assertEqual(info.htmlURL, "https://github.com/onlymasumrana/Twinly/releases/tag/v1.3.0")
        assertEqual(info.zipDownloadURL, "https://x/Twinly.zip")
        assertEqual(info.dmgDownloadURL, "https://x/Twinly.dmg")
    } catch {
        failedTests += 1
        print("❌ parseRelease failed: \(error)")
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
