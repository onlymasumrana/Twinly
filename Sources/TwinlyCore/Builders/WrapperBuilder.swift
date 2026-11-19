import Foundation
import AppKit

public final class WrapperBuilder {
    public static let shared = WrapperBuilder()

    public static var defaultApplicationsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Twinly", isDirectory: true)
    }

    public static var defaultProfilesDataDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Twinly/Profiles", isDirectory: true)
    }

    public init() {}

    public func sanitizeSlug(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return string.lowercased().components(separatedBy: allowed.inverted).filter { !$0.isEmpty }.joined(separator: "-")
    }

    public func sanitizeBundleId(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return string.components(separatedBy: allowed.inverted).joined()
    }

    public func locateLauncherBinary() throws -> URL {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["TWINLY_LAUNCHER_PATH"],
           fileManager.fileExists(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        let mainBundle = Bundle.main.bundleURL
        for rel in ["Contents/Helpers/TwinlyLauncher", "Contents/Resources/TwinlyLauncher"] {
            let candidate = mainBundle.appendingPathComponent(rel)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
        }

        var execDirs: [URL] = []
        if let exec = Bundle.main.executableURL { execDirs.append(exec.deletingLastPathComponent()) }
        execDirs.append(URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent())
        for dir in execDirs {
            let sibling = dir.appendingPathComponent("TwinlyLauncher")
            if fileManager.fileExists(atPath: sibling.path) { return sibling }
        }

        throw WrapperBuilderError.launcherBinaryNotFound("Twinly's helper is missing. Reinstall Twinly.")
    }

    private func readProfileId(ofBundleAt url: URL) -> String? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["TwinlyProfileId"] as? String
    }

    /// File name used for a shortcut (without `.app`).
    public func shortcutName(appName: String, profileName: String) -> String {
        "\(appName) (\(profileName))"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    public func buildWrapper(
        analysis: AppAnalysis,
        profileName: String,
        badgeColorHex: String,
        badgeText: String,
        customArgs: [String] = [],
        customEnv: [String: String] = [:],
        customTargetDir: URL? = nil,
        customProfilesDataDir: URL? = nil,
        separateDockIcon: Bool? = nil,
        existing: Profile? = nil
    ) throws -> Profile {
        let useClone = (separateDockIcon ?? existing?.separateDockIcon ?? false) && analysis.strategy != .sandboxedUnsupported
        guard analysis.strategy != .sandboxedUnsupported else {
            throw WrapperBuilderError.unsupportedApp(analysis.warning ?? "Sandboxed apps cannot be isolated.")
        }

        let profileId = existing?.id ?? UUID()
        let fileManager = FileManager.default

        let appsDir = customTargetDir ?? Self.defaultApplicationsDir
        try fileManager.createDirectory(at: appsDir, withIntermediateDirectories: true)

        let wrapperName = "\(shortcutName(appName: analysis.appName, profileName: profileName)).app"
        let wrapperURL = appsDir.appendingPathComponent(wrapperName)

        if fileManager.fileExists(atPath: wrapperURL.path) {
            let existingId = readProfileId(ofBundleAt: wrapperURL)
            if existingId != profileId.uuidString {
                throw WrapperBuilderError.nameConflict("Another profile already uses the name “\(shortcutName(appName: analysis.appName, profileName: profileName))”.")
            }
        }

        let profileDataDir: URL
        if let existing = existing {
            profileDataDir = URL(fileURLWithPath: existing.profileDirectory)
        } else {
            let baseProfilesDir = customProfilesDataDir ?? Self.defaultProfilesDataDir
            profileDataDir = baseProfilesDir.appendingPathComponent(profileId.uuidString)
        }
        try fileManager.createDirectory(at: profileDataDir, withIntermediateDirectories: true)

        if analysis.strategy == .genericNonSandboxed {
            let homeURL = profileDataDir.appendingPathComponent("home")
            try fileManager.createDirectory(at: homeURL.appendingPathComponent("Library/Application Support"), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: homeURL.appendingPathComponent("Library/Preferences"), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: homeURL.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        }

        // Build into a temp bundle so a failure never destroys a working shortcut.
        let tmpURL = appsDir.appendingPathComponent(".twinly-tmp-\(UUID().uuidString).app")
        defer { try? fileManager.removeItem(at: tmpURL) }

        let contentsURL = tmpURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        let launcherSource = try locateLauncherBinary()
        let bundleId = "io.twinly.\(sanitizeBundleId(analysis.bundleIdentifier)).\(profileId.uuidString.prefix(8).lowercased())"
        let displayName = "\(analysis.appName) (\(profileName))"

        if useClone {
            try cloneOriginal(analysis.appURL, to: tmpURL)
            let execName = URL(fileURLWithPath: analysis.executablePath).lastPathComponent
            let execURL = macosURL.appendingPathComponent(execName)
            let origURL = macosURL.appendingPathComponent("\(execName).twinly-orig")
            if !fileManager.fileExists(atPath: origURL.path) {
                try fileManager.moveItem(at: execURL, to: origURL)
            }
            if fileManager.fileExists(atPath: execURL.path) { try fileManager.removeItem(at: execURL) }
            try fileManager.copyItem(at: launcherSource, to: execURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)

            let plistURL = contentsURL.appendingPathComponent("Info.plist")
            let data = try Data(contentsOf: plistURL)
            var plist = (try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]) ?? [:]
            plist["CFBundleIdentifier"] = bundleId
            plist["CFBundleName"] = displayName
            plist["CFBundleDisplayName"] = displayName
            plist["CFBundleIconFile"] = "AppIcon"
            plist.removeValue(forKey: "CFBundleIconName")
            plist["TwinlyProfileId"] = profileId.uuidString
            plist["TwinlyOriginalApp"] = analysis.appURL.path
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        } else {
            try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

            let launcherTarget = macosURL.appendingPathComponent("launcher")
            try fileManager.copyItem(at: launcherSource, to: launcherTarget)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherTarget.path)

            let infoPlist: [String: Any] = [
                "CFBundleDevelopmentRegion": "en",
                "CFBundleExecutable": "launcher",
                "CFBundleIconFile": "AppIcon",
                "CFBundleIdentifier": bundleId,
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": displayName,
                "CFBundleDisplayName": displayName,
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "13.0",
                "LSUIElement": false,
                "NSHighResolutionCapable": true,
                "TwinlyProfileId": profileId.uuidString,
                "TwinlyOriginalApp": analysis.appURL.path
            ]
            let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
            try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        }

        let config = LauncherConfig(
            version: 1,
            profileId: profileId,
            profileName: profileName,
            originalAppPath: analysis.appURL.path,
            executablePath: analysis.executablePath,
            strategy: analysis.strategy.rawValue,
            profileDirectory: profileDataDir.path,
            arguments: customArgs,
            environment: customEnv,
            separateDockIcon: useClone ? true : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configData = try encoder.encode(config)
        try configData.write(to: resourcesURL.appendingPathComponent("twinly.json"))

        let baseImage: NSImage
        if let iconURL = analysis.iconURL, let img = NSImage(contentsOf: iconURL) {
            baseImage = img
        } else {
            baseImage = NSWorkspace.shared.icon(forFile: analysis.appURL.path)
        }

        let badgeColor = NSColor(hex: badgeColorHex) ?? NSColor.systemBlue
        let icnsTarget = resourcesURL.appendingPathComponent("AppIcon.icns")

        do {
            try IconBadgeGenerator.shared.generateIcns(
                baseImage: baseImage,
                badgeColor: badgeColor,
                badgeText: badgeText,
                destinationURL: icnsTarget
            )
        } catch {
            NSLog("Warning: Failed to generate custom .icns: %@. Falling back to default icon.", error.localizedDescription)
            if let iconURL = analysis.iconURL {
                try? fileManager.copyItem(at: iconURL, to: icnsTarget)
            }
        }

        if useClone {
            stripQuarantine(tmpURL)
            signClone(wrapperURL: tmpURL, originalURL: analysis.appURL)
        } else {
            signWrapperAdHoc(wrapperURL: tmpURL)
        }

        // Move into place.
        if fileManager.fileExists(atPath: wrapperURL.path) {
            try fileManager.removeItem(at: wrapperURL)
        }
        try fileManager.moveItem(at: tmpURL, to: wrapperURL)

        // Remove the old bundle if the shortcut was renamed.
        if let existing = existing, existing.wrapperAppPath != wrapperURL.path,
           fileManager.fileExists(atPath: existing.wrapperAppPath),
           readProfileId(ofBundleAt: URL(fileURLWithPath: existing.wrapperAppPath)) == profileId.uuidString {
            try? fileManager.removeItem(atPath: existing.wrapperAppPath)
        }

        registerWithLaunchServices(wrapperURL: wrapperURL)

        return Profile(
            id: profileId,
            name: profileName,
            originalAppPath: analysis.appURL.path,
            originalBundleId: analysis.bundleIdentifier,
            appName: analysis.appName,
            strategy: analysis.strategy,
            badgeColorHex: badgeColorHex,
            badgeText: badgeText,
            profileDirectory: profileDataDir.path,
            wrapperAppPath: wrapperURL.path,
            customArgs: customArgs,
            customEnv: customEnv,
            createdAt: existing?.createdAt ?? Date(),
            lastLaunchedAt: existing?.lastLaunchedAt,
            separateDockIcon: useClone ? true : separateDockIcon
        )
    }

    // MARK: - APFS clone support

    @discardableResult
    private func run(_ path: String, _ args: [String], capture: Bool = false) -> (status: Int32, out: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = capture ? pipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, Data()) }
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    /// Copy-on-write clone (zero extra space on APFS); falls back to a plain copy across volumes.
    private func cloneOriginal(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if run("/bin/cp", ["-cR", source.path, destination.path]).status != 0 {
            try? fm.removeItem(at: destination)
            if run("/bin/cp", ["-R", source.path, destination.path]).status != 0 {
                throw WrapperBuilderError.buildFailed("Couldn't copy \(source.lastPathComponent).")
            }
        }
    }

    private func stripQuarantine(_ url: URL) {
        run("/usr/bin/xattr", ["-cr", url.path])
    }

    static let teamBoundEntitlementKeys: Set<String> = [
        "com.apple.application-identifier", "com.apple.developer.team-identifier",
        "keychain-access-groups", "com.apple.developer.aps-environment",
        "com.apple.developer.associated-domains"
    ]
    static let teamBoundEntitlementPrefixes = ["com.apple.developer.icloud-", "com.apple.developer.ubiquity-"]
    static let keptEntitlementPrefixes = [
        "com.apple.security.cs.", "com.apple.security.virtualization",
        "com.apple.security.network.", "com.apple.security.device."
    ]

    /// Entitlements of the original app minus team-bound ones; only runtime/virtualization/network/device keys are kept.
    public func filteredEntitlements(of appURL: URL) -> [String: Any] {
        let out = run("/usr/bin/codesign", ["-d", "--entitlements", ":-", appURL.path], capture: true).out
        guard let dict = (try? PropertyListSerialization.propertyList(from: out, format: nil)) as? [String: Any] else { return [:] }
        return dict.filter { key, _ in
            if Self.teamBoundEntitlementKeys.contains(key) { return false }
            if Self.teamBoundEntitlementPrefixes.contains(where: { key.hasPrefix($0) }) { return false }
            return Self.keptEntitlementPrefixes.contains { key.hasPrefix($0) }
        }
    }

    private func signClone(wrapperURL: URL, originalURL: URL) {
        let fm = FileManager.default
        let entitlements = filteredEntitlements(of: originalURL)

        let frameworks = wrapperURL.appendingPathComponent("Contents/Frameworks")
        if let items = try? fm.contentsOfDirectory(atPath: frameworks.path) {
            for item in items where item.hasSuffix(".framework") || item.hasSuffix(".app") || item.hasSuffix(".dylib") {
                let url = frameworks.appendingPathComponent(item)
                // Sign helpers nested in the framework first, then the framework itself.
                if let nested = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let n as URL in nested where n.pathExtension == "app" {
                        run("/usr/bin/codesign", ["--force", "--sign", "-", n.path])
                    }
                }
                run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
            }
        }

        if !entitlements.isEmpty,
           let data = try? PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0) {
            let entURL = fm.temporaryDirectory.appendingPathComponent("twinly-ent-\(UUID().uuidString).plist")
            defer { try? fm.removeItem(at: entURL) }
            if (try? data.write(to: entURL)) != nil,
               run("/usr/bin/codesign", ["--force", "--sign", "-", "--entitlements", entURL.path, wrapperURL.path]).status == 0 {
                return
            }
        }
        run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", wrapperURL.path])
    }

    public func signWrapperAdHoc(wrapperURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", wrapperURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    public func registerWithLaunchServices(wrapperURL: URL) {
        let lsregisterURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        guard FileManager.default.fileExists(atPath: lsregisterURL.path) else { return }

        let process = Process()
        process.executableURL = lsregisterURL
        process.arguments = ["-f", wrapperURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

public enum WrapperBuilderError: LocalizedError {
    case unsupportedApp(String)
    case launcherBinaryNotFound(String)
    case buildFailed(String)
    case nameConflict(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedApp(let msg): return msg
        case .launcherBinaryNotFound(let msg): return msg
        case .buildFailed(let msg): return msg
        case .nameConflict(let msg): return msg
        }
    }
}
