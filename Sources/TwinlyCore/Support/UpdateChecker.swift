import Foundation
import AppKit

/// Checks GitHub Releases for a newer Twinly and can install it in place.
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public static let latestReleaseURL = "https://api.github.com/repos/onlymasumrana/Twinly/releases/latest"

    public struct ReleaseInfo: Codable, Equatable {
        public let tagName: String
        public let name: String
        public let body: String
        public let htmlURL: String
        public let publishedAt: String?
        public let zipDownloadURL: String?
        public let dmgDownloadURL: String?

        public init(tagName: String, name: String, body: String, htmlURL: String,
                    publishedAt: String?, zipDownloadURL: String?, dmgDownloadURL: String?) {
            self.tagName = tagName; self.name = name; self.body = body; self.htmlURL = htmlURL
            self.publishedAt = publishedAt; self.zipDownloadURL = zipDownloadURL; self.dmgDownloadURL = dmgDownloadURL
        }
    }

    public enum Status: Equatable {
        case idle, checking, upToDate(version: String), available(ReleaseInfo)
        case downloading(progress: String), installing, error(String)
    }

    @Published public var status: Status = .idle
    @Published public var lastCheckedAt: Date?
    @Published public var latestAvailableRelease: ReleaseInfo?

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public var hasUpdateAvailable: Bool {
        if case .available = status { return true }
        return latestAvailableRelease != nil
    }

    public var autoCheckForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckForUpdates") as? Bool ?? true }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "autoCheckForUpdates") }
    }

    public var autoInstallUpdates: Bool {
        get { UserDefaults.standard.object(forKey: "autoInstallUpdates") as? Bool ?? false }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "autoInstallUpdates") }
    }

    public init() {}

    // MARK: Versions

    public static func normalizeVersion(_ raw: String) -> [Int] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s.split(whereSeparator: { $0 == "." || $0 == "-" }).compactMap { Int($0) }
    }

    public static func isNewerVersion(remote: String, current: String) -> Bool {
        var r = normalizeVersion(remote), c = normalizeVersion(current)
        let n = max(r.count, c.count)
        r += Array(repeating: 0, count: n - r.count)
        c += Array(repeating: 0, count: n - c.count)
        for i in 0..<n where r[i] != c[i] { return r[i] > c[i] }
        return false
    }

    // MARK: Parsing

    private struct RawRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
        let published_at: String?
        let assets: [Asset]?
    }

    public static func parseRelease(from data: Data) throws -> ReleaseInfo {
        let raw = try JSONDecoder().decode(RawRelease.self, from: data)
        let assets = raw.assets ?? []
        func url(_ ext: String) -> String? {
            assets.first { $0.name.lowercased().hasSuffix(ext) }?.browser_download_url
        }
        return ReleaseInfo(
            tagName: raw.tag_name,
            name: (raw.name?.isEmpty == false ? raw.name : nil) ?? raw.tag_name,
            body: raw.body ?? "",
            htmlURL: raw.html_url,
            publishedAt: raw.published_at,
            zipDownloadURL: url(".zip"),
            dmgDownloadURL: url(".dmg"))
    }

    // MARK: Checking

    @MainActor
    public func checkForUpdates(userInitiated: Bool = true) {
        if case .checking = status { return }
        if case .downloading = status { return }
        if case .installing = status { return }
        status = .checking
        let version = currentVersion
        Task { @MainActor in
            do {
                guard let url = URL(string: Self.latestReleaseURL) else { throw URLError(.badURL) }
                var req = URLRequest(url: url)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.setValue("Twinly/\(version)", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw NSError(domain: "UpdateChecker", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(http.statusCode)."])
                }
                let info = try Self.parseRelease(from: data)
                lastCheckedAt = Date()
                if Self.isNewerVersion(remote: info.tagName, current: version) {
                    latestAvailableRelease = info
                    status = .available(info)
                    if !userInitiated && autoInstallUpdates && info.zipDownloadURL != nil {
                        downloadAndInstall(info)
                    }
                } else {
                    latestAvailableRelease = nil
                    status = .upToDate(version: version)
                }
            } catch {
                status = userInitiated
                    ? .error("Couldn't check for updates: \(error.localizedDescription)")
                    : .idle
            }
        }
    }

    // MARK: Installing

    @MainActor
    public func downloadAndInstall(_ release: ReleaseInfo) {
        guard let zip = release.zipDownloadURL, let zipURL = URL(string: zip) else {
            if let page = URL(string: release.htmlURL) { NSWorkspace.shared.open(page) }
            return
        }
        switch status {
        case .downloading, .installing: return
        default: break
        }
        status = .downloading(progress: "Downloading Twinly \(release.tagName)…")
        Task { @MainActor in
            do {
                let work = FileManager.default.temporaryDirectory
                    .appendingPathComponent("TwinlyUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                var req = URLRequest(url: zipURL)
                req.setValue("Twinly/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (tmp, response) = try await URLSession.shared.download(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw NSError(domain: "UpdateChecker", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."])
                }
                let zipPath = work.appendingPathComponent("Twinly.zip")
                try FileManager.default.moveItem(at: tmp, to: zipPath)

                status = .installing
                let extractDir = work.appendingPathComponent("extracted")
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
                let newApp = extractDir.appendingPathComponent("Twinly.app")
                let ok = await Task.detached { () -> Bool in
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    p.arguments = ["-x", "-k", zipPath.path, extractDir.path]
                    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
                }.value
                guard ok, FileManager.default.fileExists(atPath: newApp.path) else {
                    throw NSError(domain: "UpdateChecker", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "The downloaded archive didn't contain Twinly.app."])
                }

                guard let target = Self.installTarget() else {
                    NSWorkspace.shared.activateFileViewerSelecting([newApp])
                    if let page = URL(string: release.htmlURL) { NSWorkspace.shared.open(page) }
                    status = .error("Twinly can't replace itself here. The new version was revealed in Finder; drag it to Applications.")
                    return
                }
                _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
                let sh = Process()
                sh.executableURL = URL(fileURLWithPath: "/bin/sh")
                sh.arguments = ["-c", "sleep 0.6 && open \"\(target.path)\""]
                try sh.run()
                NSApp.terminate(nil)
            } catch {
                status = .error("Couldn't install the update: \(error.localizedDescription)")
            }
        }
    }

    /// The app bundle we can overwrite, or nil if none is writable.
    private static func installTarget() -> URL? {
        let fm = FileManager.default
        let candidates = [Bundle.main.bundleURL, URL(fileURLWithPath: "/Applications/Twinly.app")]
        for url in candidates where url.pathExtension == "app" {
            let parent = url.deletingLastPathComponent().path
            guard fm.isWritableFile(atPath: parent) else { continue }
            if fm.fileExists(atPath: url.path) && !fm.isWritableFile(atPath: url.path) { continue }
            return url
        }
        return nil
    }
}
