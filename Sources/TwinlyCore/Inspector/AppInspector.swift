import Foundation
import AppKit

public final class AppInspector {
    public static let shared = AppInspector()

    public init() {}

    public func inspect(appURL: URL) throws -> AppAnalysis {
        let path = appURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw AppInspectorError.invalidAppBundle("Path is not a valid directory: \(path)")
        }

        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw AppInspectorError.missingInfoPlist("Info.plist not found in \(appURL.lastPathComponent)")
        }

        let plistData = try Data(contentsOf: infoPlistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw AppInspectorError.invalidInfoPlist("Unable to parse Info.plist")
        }

        let appName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        let bundleIdentifier = (plist["CFBundleIdentifier"] as? String) ?? "unknown.\(appName.lowercased())"

        guard let executableName = plist["CFBundleExecutable"] as? String else {
            throw AppInspectorError.missingExecutable("CFBundleExecutable missing from Info.plist")
        }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
        let executablePath = executableURL.path
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw AppInspectorError.missingExecutable("Executable binary does not exist at \(executablePath)")
        }

        // Detect frameworks
        let frameworks = detectFrameworks(in: appURL)

        // Check sandbox entitlement
        let isSandboxed = checkAppSandboxEntitlement(appURL: appURL)

        // Detect Electron / Chromium indicators
        let isElectronOrChromium = detectElectronOrChromium(appURL: appURL, frameworks: frameworks)

        let strategy: AppStrategy
        let explanation: String
        var warning: String? = nil

        if isSandboxed {
            strategy = .sandboxedUnsupported
            explanation = "This application runs inside the macOS App Sandbox. macOS locks sandbox data containers to the exact bundle identifier and developer team ID, which prevents isolated data instances without modifying or resigning the app."
            warning = "Sandboxed apps (Mac App Store apps) are not supported because their container directories are strictly governed by macOS Sandbox entitlements tied to the bundle ID."
        } else if isElectronOrChromium {
            strategy = .electronChromium
            explanation = "Detected Electron / Chromium architecture. Twinly will launch isolated instances with a dedicated --user-data-dir parameter, giving it completely separated cookies, sessions, cache, and preferences."
        } else {
            strategy = .genericNonSandboxed
            explanation = "Detected generic non-sandboxed macOS application. Twinly will launch isolated instances with a dedicated HOME directory containing redirected Library/Application Support and Library/Preferences."
        }

        let iconURL = findIconURL(appURL: appURL, plist: plist)

        return AppAnalysis(
            appURL: appURL,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath,
            strategy: strategy,
            frameworks: frameworks,
            isSandboxed: isSandboxed,
            iconURL: iconURL,
            explanation: explanation,
            warning: warning
        )
    }

    private func detectFrameworks(in appURL: URL) -> [String] {
        let frameworksURL = appURL.appendingPathComponent("Contents/Frameworks")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: frameworksURL.path) else {
            return []
        }
        return contents.filter { $0.hasSuffix(".framework") || $0.hasSuffix(".app") || $0.hasSuffix(".dylib") }
    }

    public func detectElectronOrChromium(appURL: URL, frameworks: [String]) -> Bool {
        // 1. Check frameworks
        for framework in frameworks {
            let lower = framework.lowercased()
            if lower.contains("electron") || lower.contains("chromium") || lower.contains("chrome") {
                return true
            }
        }

        // 2. Check Resources folder for electron indicators (app.asar, electron.asar)
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources")
        if FileManager.default.fileExists(atPath: resourcesURL.appendingPathComponent("app.asar").path) ||
           FileManager.default.fileExists(atPath: resourcesURL.appendingPathComponent("default_app.asar").path) ||
           FileManager.default.fileExists(atPath: resourcesURL.appendingPathComponent("electron.asar").path) {
            return true
        }

        // 3. Check for Electron Framework directly
        let electronFrameworkURL = appURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        if FileManager.default.fileExists(atPath: electronFrameworkURL.path) {
            return true
        }

        return false
    }

    public func checkAppSandboxEntitlement(appURL: URL) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", appURL.path]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if output.contains("com.apple.security.app-sandbox") && output.contains("<true/>") {
                    return true
                }
            }
        } catch {
            return false
        }
        return false
    }

    private func findIconURL(appURL: URL, plist: [String: Any]) -> URL? {
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources")
        if let iconFile = plist["CFBundleIconFile"] as? String, !iconFile.isEmpty {
            let cleanName = iconFile.hasSuffix(".icns") ? iconFile : "\(iconFile).icns"
            let iconURL = resourcesURL.appendingPathComponent(cleanName)
            if FileManager.default.fileExists(atPath: iconURL.path) {
                return iconURL
            }
        }

        // Fallback: search Resources for any .icns file
        if let files = try? FileManager.default.contentsOfDirectory(atPath: resourcesURL.path) {
            if let icns = files.first(where: { $0.hasSuffix(".icns") }) {
                return resourcesURL.appendingPathComponent(icns)
            }
        }

        return nil
    }
}

public enum AppInspectorError: LocalizedError {
    case invalidAppBundle(String)
    case missingInfoPlist(String)
    case invalidInfoPlist(String)
    case missingExecutable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAppBundle(let msg): return "Invalid app bundle: \(msg)"
        case .missingInfoPlist(let msg): return "Missing Info.plist: \(msg)"
        case .invalidInfoPlist(let msg): return "Invalid Info.plist: \(msg)"
        case .missingExecutable(let msg): return "Missing executable: \(msg)"
        }
    }
}
