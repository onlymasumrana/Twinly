import Foundation
import AppKit

struct LauncherConfig: Codable {
    var version: Int
    var profileId: UUID
    var profileName: String
    var originalAppPath: String
    var executablePath: String
    var strategy: String
    var profileDirectory: String
    var arguments: [String]
    var environment: [String: String]
}

func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Open Twinly")
    let response = alert.runModal()
    if response == .alertSecondButtonReturn {
        // Attempt to open Twinly if installed
        let twinlyApp = URL(fileURLWithPath: "/Applications/Twinly.app")
        if FileManager.default.fileExists(atPath: twinlyApp.path) {
            NSWorkspace.shared.open(twinlyApp)
        } else {
            let userTwinlyApp = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Twinly.app")
            if FileManager.default.fileExists(atPath: userTwinlyApp.path) {
                NSWorkspace.shared.open(userTwinlyApp)
            }
        }
    }
}

func locateConfigFile() -> URL? {
    let bundle = Bundle.main
    if let url = bundle.url(forResource: "twinly", withExtension: "json") {
        return url
    }
    // Check Resources relative to executable
    let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let resourcesConfig = execURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/twinly.json")
    if FileManager.default.fileExists(atPath: resourcesConfig.path) {
        return resourcesConfig
    }
    // Check same folder as executable
    let sameDirConfig = execURL.deletingLastPathComponent().appendingPathComponent("twinly.json")
    if FileManager.default.fileExists(atPath: sameDirConfig.path) {
        return sameDirConfig
    }
    return nil
}

func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // Do not steal focus permanently or stay in Dock

    guard let configURL = locateConfigFile() else {
        showAlert(
            title: "Twinly Launcher Error",
            message: "Missing twinly.json configuration file inside the application bundle."
        )
        exit(1)
    }

    guard let data = try? Data(contentsOf: configURL),
          let config = try? JSONDecoder().decode(LauncherConfig.self, from: data) else {
        showAlert(
            title: "Twinly Launcher Error",
            message: "Unable to read or decode twinly.json configuration file."
        )
        exit(1)
    }

    // Verify original app exists
    let originalAppURL = URL(fileURLWithPath: config.originalAppPath)
    guard FileManager.default.fileExists(atPath: originalAppURL.path) else {
        showAlert(
            title: "Original Application Not Found",
            message: "The original application '\(originalAppURL.lastPathComponent)' was moved or deleted from:\n\(config.originalAppPath)\n\nPlease reinstall the application or rebuild the profile in Twinly."
        )
        exit(1)
    }

    // Prepare profile directory
    let profileDirURL = URL(fileURLWithPath: config.profileDirectory)
    let fileManager = FileManager.default

    var launchEnv = ProcessInfo.processInfo.environment
    for (key, val) in config.environment {
        launchEnv[key] = val
    }

    var launchArgs = [String]()

    if config.strategy == "electronChromium" {
        try? fileManager.createDirectory(at: profileDirURL, withIntermediateDirectories: true)
        launchArgs.append("--user-data-dir=\(config.profileDirectory)")
        // For Chrome-style browsers, also isolate profile directory
        let origLower = config.originalAppPath.lowercased()
        if origLower.contains("chrome") || origLower.contains("brave") || origLower.contains("edge") || origLower.contains("chromium") {
            launchArgs.append("--profile-directory=Default")
        }
    } else if config.strategy == "genericNonSandboxed" {
        let isolatedHome = profileDirURL.appendingPathComponent("home")
        let appSupport = isolatedHome.appendingPathComponent("Library/Application Support")
        let prefs = isolatedHome.appendingPathComponent("Library/Preferences")
        let caches = isolatedHome.appendingPathComponent("Library/Caches")

        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: prefs, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: caches, withIntermediateDirectories: true)

        launchEnv["HOME"] = isolatedHome.path
    }

    // Append custom args
    launchArgs.append(contentsOf: config.arguments)

    // Touch last launched timestamp
    let timestampFile = profileDirURL.appendingPathComponent(".last_launched")
    let nowString = ISO8601DateFormatter().string(from: Date())
    try? nowString.write(to: timestampFile, atomically: true, encoding: .utf8)

    // Attempt launch using NSWorkspace.OpenConfiguration
    let openConfig = NSWorkspace.OpenConfiguration()
    openConfig.arguments = launchArgs
    openConfig.environment = launchEnv
    openConfig.createsNewApplicationInstance = true
    openConfig.activates = true

    let semaphore = DispatchSemaphore(value: 0)
    var workspaceLaunchSucceeded = false

    NSWorkspace.shared.openApplication(at: originalAppURL, configuration: openConfig) { runningApp, error in
        if let error = error {
            NSLog("NSWorkspace openApplication error: %@", error.localizedDescription)
            workspaceLaunchSucceeded = false
        } else {
            workspaceLaunchSucceeded = true
        }
        semaphore.signal()
    }

    _ = semaphore.wait(timeout: .now() + 2.5)

    // If NSWorkspace failed, fallback to direct binary execution
    if !workspaceLaunchSucceeded {
        let execURL = URL(fileURLWithPath: config.executablePath)
        if fileManager.fileExists(atPath: execURL.path) {
            let process = Process()
            process.executableURL = execURL
            process.arguments = launchArgs
            process.environment = launchEnv
            do {
                try process.run()
            } catch {
                showAlert(
                    title: "Launch Failed",
                    message: "Failed to launch application binary:\n\(error.localizedDescription)"
                )
                exit(1)
            }
        } else {
            showAlert(
                title: "Launch Failed",
                message: "Could not open application bundle or executable binary at \(config.executablePath)."
            )
            exit(1)
        }
    }

    exit(0)
}

main()
