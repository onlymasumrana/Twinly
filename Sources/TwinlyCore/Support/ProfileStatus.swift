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

    public static func isRunning(_ p: Profile) -> Bool {
        p.strategy == .electronChromium && isRunning(profileDirectory: p.profileDirectory)
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
        "com.openai.chat", "notion.id", "com.figma.Desktop", "md.obsidian"
    ]

    public static func installed() -> [URL] {
        bundleIdentifiers.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }
}
