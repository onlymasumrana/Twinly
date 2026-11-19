import Foundation
import AppKit

import TwinlyCore

func openTwinly() {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.twinly.Twinly") {
        NSWorkspace.shared.open(url)
        return
    }
    let candidates = [
        URL(fileURLWithPath: "/Applications/Twinly.app"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Twinly.app")
    ]
    if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        NSWorkspace.shared.open(found)
    }
}

func showAlert(title: String, message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Open Twinly")
    let response = alert.runModal()
    if response == .alertSecondButtonReturn {
        openTwinly()
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
            title: "Can't Open This Profile",
            message: "This shortcut is damaged. Open Twinly and choose Repair All Shortcuts."
        )
        exit(1)
    }

    guard let data = try? Data(contentsOf: configURL),
          let config = try? JSONDecoder().decode(LauncherConfig.self, from: data) else {
        showAlert(
            title: "Can't Open This Profile",
            message: "This shortcut is damaged. Open Twinly and choose Repair All Shortcuts."
        )
        exit(1)
    }

    // Verify original app exists
    let originalAppURL = URL(fileURLWithPath: config.originalAppPath)
    guard FileManager.default.fileExists(atPath: originalAppURL.path) else {
        showAlert(
            title: "“\(originalAppURL.deletingPathExtension().lastPathComponent)” Can't Be Found",
            message: "It was moved or deleted from \(config.originalAppPath). Reinstall it, then open Twinly and choose Repair All Shortcuts."
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
    } else if config.strategy == "firefoxGecko" {
        try? fileManager.createDirectory(at: profileDirURL, withIntermediateDirectories: true)
        launchArgs.append(contentsOf: ["-no-remote", "-profile", config.profileDirectory])
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

    // Separate Dock icon mode: this bundle is an APFS clone of the original app whose real
    // executable was renamed to `<exec>.twinly-orig`. execv replaces this process in place, so the
    // PID and bundle path stay ours and the Dock keeps the badged icon and "App (Profile)" name.
    let currentExec = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let origExec = currentExec + ".twinly-orig"
    let isClone = fileManager.fileExists(atPath: origExec)
    let originalChanged = isClone && !OriginalAppVersion(appURL: originalAppURL)
        .matches(stampedInfo: Bundle.main.infoDictionary ?? [:])
    if originalChanged {
        try? fileManager.createDirectory(at: profileDirURL, withIntermediateDirectories: true)
        try? Data().write(to: profileDirURL.appendingPathComponent(".needs_rebuild"), options: .atomic)
    }
    if isClone && !originalChanged {
        for (key, val) in launchEnv { setenv(key, val, 1) }
        let argv = [origExec] + launchArgs
        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgs.append(nil)
        execv(origExec, &cArgs)
        let err = String(cString: strerror(errno))
        showAlert(title: "Couldn't Open “\(originalAppURL.deletingPathExtension().lastPathComponent)”", message: err)
        exit(1)
    }

    // Attempt launch using NSWorkspace.OpenConfiguration
    let openConfig = NSWorkspace.OpenConfiguration()
    openConfig.arguments = launchArgs
    openConfig.environment = launchEnv
    openConfig.createsNewApplicationInstance = true
    openConfig.activates = true

    enum Outcome { case pending, ok, failed(Error) }
    let lock = NSLock()
    var outcome = Outcome.pending
    let semaphore = DispatchSemaphore(value: 0)
    let appName = originalAppURL.deletingPathExtension().lastPathComponent

    NSWorkspace.shared.openApplication(at: originalAppURL, configuration: openConfig) { _, error in
        lock.lock()
        if let error = error {
            NSLog("NSWorkspace openApplication error: %@", error.localizedDescription)
            outcome = .failed(error)
        } else {
            outcome = .ok
        }
        lock.unlock()
        semaphore.signal()
    }

    // Slow cold starts (Electron) can take a while. On timeout, assume it is still launching.
    _ = semaphore.wait(timeout: .now() + 15)

    lock.lock()
    let finalOutcome = outcome
    lock.unlock()

    if case .failed = finalOutcome {
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
                    title: "Couldn't Open “\(appName)”",
                    message: error.localizedDescription
                )
                exit(1)
            }
        } else {
            showAlert(
                title: "Couldn't Open “\(appName)”",
                message: "macOS couldn't start the app at \(config.originalAppPath)."
            )
            exit(1)
        }
    }

    exit(0)
}

main()
