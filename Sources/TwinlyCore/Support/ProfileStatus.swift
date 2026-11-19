import Foundation
import AppKit

public enum ProfileStatus {
    /// Chromium/Electron apps keep a `SingletonLock` symlink whose target is "<host>-<pid>".
    public static func isRunning(profileDirectory: String) -> Bool {
        let lock = (profileDirectory as NSString).appendingPathComponent("SingletonLock")
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: lock),
              let pidString = target.split(separator: "-").last,
              let pid = Int32(pidString), pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Firefox keeps `.parentlock` / `parent.lock` (locked with fcntl while running); older builds use a `lock` symlink with the pid.
    public static func isFirefoxRunning(profileDirectory: String) -> Bool {
        let fm = FileManager.default
        let lock = (profileDirectory as NSString).appendingPathComponent("lock")
        if let target = try? fm.destinationOfSymbolicLink(atPath: lock),
           let pidString = target.split(separator: "+").last, let pid = Int32(pidString), pid > 0 {
            if kill(pid, 0) == 0 || errno == EPERM { return true }
        }
        for name in [".parentlock", "parent.lock"] {
            let path = (profileDirectory as NSString).appendingPathComponent(name)
            guard fm.fileExists(atPath: path) else { continue }
            // The file persists after exit; only a held lock means running.
            let fd = open(path, O_RDWR)
            if fd < 0 { continue }
            defer { close(fd) }
            var fl = flock()
            fl.l_type = Int16(F_WRLCK); fl.l_whence = Int16(SEEK_SET); fl.l_start = 0; fl.l_len = 0
            if fcntl(fd, F_GETLK, &fl) == 0, fl.l_type != Int16(F_UNLCK) { return true }
        }
        return false
    }

    public static func runningApplications(for p: Profile) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == p.wrapperAppPath }
    }

    public static func isRunning(_ p: Profile) -> Bool {
        if !runningApplications(for: p).isEmpty { return true }
        if isRunning(profileDirectory: p.profileDirectory) { return true }
        if p.strategy == .firefoxGecko { return isFirefoxRunning(profileDirectory: p.profileDirectory) }
        return false
    }

    public static func lastOpened(_ p: Profile) -> Date? {
        let file = (p.profileDirectory as NSString).appendingPathComponent(".last_launched")
        let fileDate = (try? FileManager.default.attributesOfItem(atPath: file))?[.modificationDate] as? Date
        switch (p.lastLaunchedAt, fileDate) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    public static func isOriginalMissing(_ p: Profile) -> Bool {
        !FileManager.default.fileExists(atPath: p.originalAppPath)
    }
}

public enum KnownApps {
    public static let bundleIdentifiers = [
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.google.Chrome", "com.brave.Browser",
        "com.microsoft.edgemac", "com.microsoft.VSCode", "com.anthropic.claudefordesktop",
        "com.openai.chat", "notion.id", "com.figma.Desktop", "md.obsidian",
        "org.mozilla.firefox", "app.zen-browser.zen"
    ]

    public static func installed() -> [URL] {
        bundleIdentifiers.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }
}
