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

        // 1. Check in Twinly.app bundle (Helpers or Resources)
        if let bundle = Bundle.main.url(forResource: "TwinlyLauncher", withExtension: nil) {
            return bundle
        }
        let mainBundle = Bundle.main.bundleURL
        let candidateInHelpers = mainBundle.appendingPathComponent("Contents/Helpers/TwinlyLauncher")
        if fileManager.fileExists(atPath: candidateInHelpers.path) {
            return candidateInHelpers
        }
        let candidateInResources = mainBundle.appendingPathComponent("Contents/Resources/TwinlyLauncher")
        if fileManager.fileExists(atPath: candidateInResources.path) {
            return candidateInResources
        }

        // 2. Check next to running executable
        let currentExec = URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = currentExec.deletingLastPathComponent().appendingPathComponent("TwinlyLauncher")
        if fileManager.fileExists(atPath: sibling.path) {
            return sibling
        }

        // 3. Check standard build directories relative to current directory and home
        let searchPaths = [
            ".build/debug/TwinlyLauncher",
            ".build/release/TwinlyLauncher",
            "build/TwinlyLauncher",
            "/usr/local/bin/TwinlyLauncher"
        ]

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for rel in searchPaths {
            let candidate = cwd.appendingPathComponent(rel)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // 4. Check scratch/Twinly/.build
        let scratchCandidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/scratch/Twinly/.build/debug/TwinlyLauncher")
        if fileManager.fileExists(atPath: scratchCandidate.path) {
            return scratchCandidate
        }

        let scratchReleaseCandidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/scratch/Twinly/.build/release/TwinlyLauncher")
        if fileManager.fileExists(atPath: scratchReleaseCandidate.path) {
            return scratchReleaseCandidate
        }

        throw WrapperBuilderError.launcherBinaryNotFound(
            "TwinlyLauncher binary could not be found. Please ensure TwinlyLauncher is built."
        )
    }

    public func buildWrapper(
        analysis: AppAnalysis,
        profileName: String,
        badgeColorHex: String,
        badgeText: String,
        customArgs: [String] = [],
        customEnv: [String: String] = [:],
        customTargetDir: URL? = nil,
        customProfilesDataDir: URL? = nil
    ) throws -> Profile {
        guard analysis.strategy != .sandboxedUnsupported else {
            throw WrapperBuilderError.unsupportedApp(analysis.warning ?? "Sandboxed apps cannot be isolated.")
        }

        let profileId = UUID()
        let fileManager = FileManager.default

        // Output applications folder
        let appsDir = customTargetDir ?? Self.defaultApplicationsDir
        try fileManager.createDirectory(at: appsDir, withIntermediateDirectories: true)

        // Wrapper .app path
        let safeAppName = analysis.appName.replacingOccurrences(of: "/", with: "-")
        let safeProfileName = profileName.replacingOccurrences(of: "/", with: "-")
        let wrapperName = "\(safeAppName) (\(safeProfileName)).app"
        let wrapperURL = appsDir.appendingPathComponent(wrapperName)

        // If exists, remove old wrapper
        if fileManager.fileExists(atPath: wrapperURL.path) {
            try fileManager.removeItem(at: wrapperURL)
        }

        // Profile data directory
        let baseProfilesDir = customProfilesDataDir ?? Self.defaultProfilesDataDir
        let profileDataDir = baseProfilesDir.appendingPathComponent(profileId.uuidString)
        try fileManager.createDirectory(at: profileDataDir, withIntermediateDirectories: true)

        if analysis.strategy == .genericNonSandboxed {
            let homeURL = profileDataDir.appendingPathComponent("home")
            try fileManager.createDirectory(at: homeURL.appendingPathComponent("Library/Application Support"), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: homeURL.appendingPathComponent("Library/Preferences"), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: homeURL.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        }

        // Build wrapper bundle structure
        let contentsURL = wrapperURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        // Copy launcher binary
        let launcherSource = try locateLauncherBinary()
        let launcherTarget = macosURL.appendingPathComponent("launcher")
        try fileManager.copyItem(at: launcherSource, to: launcherTarget)

        // Set executable permissions
        var perms = try fileManager.attributesOfItem(atPath: launcherTarget.path)
        perms[.posixPermissions] = 0o755
        try fileManager.setAttributes(perms, ofItemAtPath: launcherTarget.path)

        // Generate Info.plist
        let profileSlug = sanitizeSlug(profileName)
        let bundleId = "io.twinly.\(sanitizeBundleId(analysis.bundleIdentifier)).\(profileSlug)"

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

        // Generate twinly.json
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

        // Generate badged icon
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

        // Ad-hoc sign wrapper
        signWrapperAdHoc(wrapperURL: wrapperURL)

        // Register with LaunchServices
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
            createdAt: Date(),
            lastLaunchedAt: nil
        )
    }

    public func signWrapperAdHoc(wrapperURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", wrapperURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    public func registerWithLaunchServices(wrapperURL: URL) {
        let lsregisterURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        guard FileManager.default.fileExists(atPath: lsregisterURL.path) else { return }

        let process = Process()
        process.executableURL = lsregisterURL
        process.arguments = ["-f", wrapperURL.path]
        try? process.run()
        process.waitUntilExit()
    }
}

public enum WrapperBuilderError: LocalizedError {
    case unsupportedApp(String)
    case launcherBinaryNotFound(String)
    case buildFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedApp(let msg): return msg
        case .launcherBinaryNotFound(let msg): return msg
        case .buildFailed(let msg): return msg
        }
    }
}
