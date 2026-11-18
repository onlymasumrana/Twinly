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
        existing: Profile? = nil
    ) throws -> Profile {
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

        try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let launcherSource = try locateLauncherBinary()
        let launcherTarget = macosURL.appendingPathComponent("launcher")
        try fileManager.copyItem(at: launcherSource, to: launcherTarget)

        var perms = try fileManager.attributesOfItem(atPath: launcherTarget.path)
        perms[.posixPermissions] = 0o755
        try fileManager.setAttributes(perms, ofItemAtPath: launcherTarget.path)

        let bundleId = "io.twinly.\(sanitizeBundleId(analysis.bundleIdentifier)).\(profileId.uuidString.prefix(8).lowercased())"

        let infoPlist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "launcher",
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": bundleId,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "\(analysis.appName) (\(profileName))",
            "CFBundleDisplayName": "\(analysis.appName) (\(profileName))",
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

        let config = LauncherConfig(
            version: 1,
            profileId: profileId,
            profileName: profileName,
            originalAppPath: analysis.appURL.path,
            executablePath: analysis.executablePath,
            strategy: analysis.strategy.rawValue,
            profileDirectory: profileDataDir.path,
            arguments: customArgs,
            environment: customEnv
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

        signWrapperAdHoc(wrapperURL: tmpURL)

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
            lastLaunchedAt: existing?.lastLaunchedAt
        )
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
