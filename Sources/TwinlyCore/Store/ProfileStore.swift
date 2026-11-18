import Foundation
import AppKit

public struct RepairResult {
    public var repaired: [String]
    public var failed: [String]
    public init(repaired: [String] = [], failed: [String] = []) {
        self.repaired = repaired
        self.failed = failed
    }
}

public enum StoreError: LocalizedError {
    case notFound
    case shortcutMissing(String)
    case terminalLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "That profile no longer exists."
        case .shortcutMissing: return "This shortcut is missing. Choose Repair All Shortcuts in Settings."
        case .terminalLaunchFailed(let m): return m
        }
    }
}

public final class ProfileStore: ObservableObject {
    public static let shared = ProfileStore()

    @Published public var profiles: [Profile] = []
    @Published public var cliProfiles: [CLIProfile] = []
    @Published public var loadError: String?

    public let baseStorageDir: URL
    private let profilesFileURL: URL
    private let cliProfilesFileURL: URL

    public init(baseStorageDir: URL? = nil) {
        let base = baseStorageDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Twinly", isDirectory: true)
        self.baseStorageDir = base
        self.profilesFileURL = base.appendingPathComponent("profiles.json")
        self.cliProfilesFileURL = base.appendingPathComponent("cli_profiles.json")

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Persistence

    private func loadFile<T: Decodable>(_ url: URL, as type: [T].Type) -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).broken-\(stamp)")
            try? FileManager.default.copyItem(at: url, to: backup)
            loadError = "Twinly couldn't read your profiles. A backup was saved to \(backup.path)."
            return []
        }
    }

    public func load() {
        loadError = nil
        profiles = loadFile(profilesFileURL, as: [Profile].self)
        cliProfiles = loadFile(cliProfilesFileURL, as: [CLIProfile].self)
    }

    private func write<T: Encodable>(_ value: [T], to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            loadError = "Twinly couldn't save your profiles: \(error.localizedDescription)"
        }
    }

    public func saveProfiles() { write(profiles, to: profilesFileURL) }
    public func saveCLIProfiles() { write(cliProfiles, to: cliProfilesFileURL) }

    // MARK: - GUI Profiles Management

    public func addProfile(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        saveProfiles()
    }

    public func updateProfile(_ profile: Profile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            saveProfiles()
        }
    }

    /// Rebuilds the shortcut for an edited profile, keeping its id and data. Blocking; call off the main thread.
    /// The store itself is updated on the main thread.
    public func updateAndRebuild(_ profile: Profile) throws -> Profile {
        let analysis = try AppInspector.shared.inspect(appURL: URL(fileURLWithPath: profile.originalAppPath))
        let rebuilt = try WrapperBuilder.shared.buildWrapper(
            analysis: analysis,
            profileName: profile.name,
            badgeColorHex: profile.badgeColorHex,
            badgeText: profile.badgeText,
            customArgs: profile.customArgs,
            customEnv: profile.customEnv,
            existing: profile
        )
        onMain { self.updateProfile(rebuilt) }
        return rebuilt
    }

    public func duplicateProfile(_ profile: Profile) throws -> Profile {
        let analysis = try AppInspector.shared.inspect(appURL: URL(fileURLWithPath: profile.originalAppPath))
        var name = "\(profile.name) Copy"
        var n = 2
        let current: [Profile] = Thread.isMainThread ? profiles : DispatchQueue.main.sync { profiles }
        let taken = Set(current.filter { $0.originalAppPath == profile.originalAppPath }.map { $0.name.lowercased() })
        while taken.contains(name.lowercased()) { name = "\(profile.name) Copy \(n)"; n += 1 }

        let text: String
        if let num = Int(profile.badgeText) { text = String(min(num + 1, 99)) } else { text = profile.badgeText }

        let built = try WrapperBuilder.shared.buildWrapper(
            analysis: analysis,
            profileName: name,
            badgeColorHex: profile.badgeColorHex,
            badgeText: text,
            customArgs: profile.customArgs,
            customEnv: profile.customEnv
        )
        onMain { self.addProfile(built) }
        return built
    }

    public func deleteProfile(id: UUID, deleteData: Bool) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw StoreError.notFound }

        let fileManager = FileManager.default

        let wrapperURL = URL(fileURLWithPath: profile.wrapperAppPath)
        if fileManager.fileExists(atPath: wrapperURL.path) {
            try fileManager.removeItem(at: wrapperURL)
        }

        if deleteData {
            let dataURL = URL(fileURLWithPath: profile.profileDirectory)
            if fileManager.fileExists(atPath: dataURL.path) {
                try fileManager.removeItem(at: dataURL)
            }
        }

        profiles.removeAll { $0.id == id }
        saveProfiles()
    }

    public func launchProfile(_ profile: Profile, completion: @escaping (Error?) -> Void = { _ in }) {
        let wrapperURL = URL(fileURLWithPath: profile.wrapperAppPath)
        guard FileManager.default.fileExists(atPath: wrapperURL.path) else {
            completion(StoreError.shortcutMissing(profile.wrapperAppPath))
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: wrapperURL, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                if error == nil, let idx = self?.profiles.firstIndex(where: { $0.id == profile.id }) {
                    self?.profiles[idx].lastLaunchedAt = Date()
                    self?.saveProfiles()
                }
                completion(error)
            }
        }
    }

    /// Rebuilds every shortcut, keeping each profile's id and data. Blocking; call off the main thread.
    public func rebuildAllWrappers(targetDir: URL? = nil, dataDir: URL? = nil) -> RepairResult {
        var result = RepairResult()
        var updated: [Profile] = []
        let snapshot: [Profile] = Thread.isMainThread ? profiles : DispatchQueue.main.sync { profiles }

        for profile in snapshot {
            let label = "\(profile.appName) (\(profile.name))"
            let origURL = URL(fileURLWithPath: profile.originalAppPath)
            guard FileManager.default.fileExists(atPath: origURL.path) else {
                result.failed.append("\(label): app not found")
                continue
            }
            do {
                let analysis = try AppInspector.shared.inspect(appURL: origURL)
                let rebuilt = try WrapperBuilder.shared.buildWrapper(
                    analysis: analysis,
                    profileName: profile.name,
                    badgeColorHex: profile.badgeColorHex,
                    badgeText: profile.badgeText,
                    customArgs: profile.customArgs,
                    customEnv: profile.customEnv,
                    customTargetDir: targetDir,
                    customProfilesDataDir: dataDir,
                    existing: profile
                )
                updated.append(rebuilt)
                result.repaired.append(label)
            } catch {
                result.failed.append("\(label): \(error.localizedDescription)")
            }
        }

        let apply = {
            for p in updated {
                if let idx = self.profiles.firstIndex(where: { $0.id == p.id }) { self.profiles[idx] = p }
            }
            self.saveProfiles()
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.sync { apply() } }
        return result
    }

    // MARK: - CLI Profiles Management

    public func addCLIProfile(_ profile: CLIProfile) {
        cliProfiles.removeAll { $0.id == profile.id }
        cliProfiles.append(profile)
        saveCLIProfiles()
    }

    public func updateCLIProfile(_ profile: CLIProfile) {
        if let idx = cliProfiles.firstIndex(where: { $0.id == profile.id }) {
            cliProfiles[idx] = profile
            saveCLIProfiles()
        } else {
            addCLIProfile(profile)
        }
    }

    public func deleteCLIProfile(id: UUID, deleteData: Bool) throws {
        guard let profile = cliProfiles.first(where: { $0.id == id }) else { throw StoreError.notFound }

        let fileManager = FileManager.default

        let sharedByOthers = cliProfiles.contains { $0.id != id && $0.wrapperScriptPath == profile.wrapperScriptPath }
        if !sharedByOthers,
           fileManager.fileExists(atPath: profile.wrapperScriptPath),
           ShellEnvironment.hasTwinlyMarker(path: profile.wrapperScriptPath) {
            try fileManager.removeItem(atPath: profile.wrapperScriptPath)
        }

        if deleteData {
            let sharedDir = cliProfiles.contains { $0.id != id && $0.profileDirectory == profile.profileDirectory }
            if !sharedDir, fileManager.fileExists(atPath: profile.profileDirectory) {
                try fileManager.removeItem(atPath: profile.profileDirectory)
            }
        }

        cliProfiles.removeAll { $0.id == id }
        saveCLIProfiles()
    }

    public func launchCLIInTerminal(_ profile: CLIProfile, completion: @escaping (Error?) -> Void = { _ in }) {
        do {
            let dir = baseStorageDir.appendingPathComponent("TerminalLaunchers", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(profile.commandName).command")
            let body = "#!/bin/sh\nexec \(ShellEnvironment.shellQuote(profile.wrapperScriptPath))\n"
            try body.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                DispatchQueue.main.async {
                    if error == nil, let idx = self?.cliProfiles.firstIndex(where: { $0.id == profile.id }) {
                        self?.cliProfiles[idx].lastLaunchedAt = Date()
                        self?.saveCLIProfiles()
                    }
                    completion(error)
                }
            }
        } catch {
            completion(error)
        }
    }

    // MARK: - Utilities

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    }

    public func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    public func openFolder(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
