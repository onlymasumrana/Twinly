import Foundation

/// Reads the on-disk plist rather than Bundle's cached metadata after an app update.
public struct OriginalAppVersion {
    public let shortVersion: String
    public let bundleVersion: String

    public init(appURL: URL) {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let info = (try? Data(contentsOf: plistURL)).flatMap {
            (try? PropertyListSerialization.propertyList(from: $0, format: nil)) as? [String: Any]
        } ?? [:]
        let executable = info["CFBundleExecutable"] as? String ?? appURL.deletingPathExtension().lastPathComponent
        let executableURL = appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path)
        let date = attributes?[.modificationDate] as? Date
        let fallback = "mtime:\(date?.timeIntervalSince1970 ?? 0)"
        shortVersion = (info["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        bundleVersion = (info["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

    public func matches(stampedInfo: [String: Any]) -> Bool {
        stampedInfo["TwinlyOriginalShortVersion"] as? String == shortVersion &&
        stampedInfo["TwinlyOriginalBundleVersion"] as? String == bundleVersion
    }
}
