import Foundation
import AppKit

public final class ProfileStore: ObservableObject {
    public static let shared = ProfileStore()

    @Published public var profiles: [Profile] = []
    @Published public var cliProfiles: [CLIProfile] = []

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

    public func load() {
        let decoder = JSONDecoder()

        if let data = try? Data(contentsOf: profilesFileURL),
           let decoded = try? decoder.decode([Profile].self, from: data) {
            self.profiles = decoded
        } else {
            self.profiles = []
        }

        if let cliData = try? Data(contentsOf: cliProfilesFileURL),
           let decodedCLI = try? decoder.decode([CLIProfile].self, from: cliData) {
            self.cliProfiles = decodedCLI
        } else {
            self.cliProfiles = []
        }
    }

    public func saveProfiles() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: profilesFileURL, options: .atomic)
        }
    }

    public func saveCLIProfiles() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cliProfiles) {
            try? data.write(to: cliProfilesFileURL, options: .atomic)
        }
    }

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

    public func deleteProfile(id: UUID, deleteData: Bool) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }

        let fileManager = FileManager.default

        // 1. Delete wrapper .app bundle
        let wrapperURL = URL(fileURLWithPath: profile.wrapperAppPath)
        if fileManager.fileExists(atPath: wrapperURL.path) {
            try fileManager.removeItem(at: wrapperURL)
        }

        // 2. Conditionally delete profile data directory
        if deleteData {
            let dataURL = URL(fileURLWithPath: profile.profileDirectory)
            if fileManager.fileExists(atPath: dataURL.path) {
                try fileManager.removeItem(at: dataURL)
            }
        }

        profiles.removeAll { $0.id == id }
        saveProfiles()
    }

    public func launchProfile(_ profile: Profile) {
        let wrapperURL = URL(fileURLWithPath: profile.wrapperAppPath)
        guard FileManager.default.fileExists(atPath: wrapperURL.path) else {
            NSLog("Wrapper does not exist at: %@", profile.wrapperAppPath)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: wrapperURL, configuration: config) { [weak self] _, _ in
            DispatchQueue.main.async {
                if let idx = self?.profiles.firstIndex(where: { $0.id == profile.id }) {
                    self?.profiles[idx].lastLaunchedAt = Date()
                    self?.saveProfiles()
                }
            }
        }
    }

    public func rebuildAllWrappers() -> (rebuilt: [String], failed: [String]) {
        var rebuilt: [String] = []
        var failed: [String] = []

        for profile in profiles {
            let origURL = URL(fileURLWithPath: profile.originalAppPath)
            guard FileManager.default.fileExists(atPath: origURL.path) else {
                failed.append("\(profile.appName) (\(profile.name)): Original app not found at \(profile.originalAppPath)")
                continue
            }

            do {
                let analysis = try AppInspector.shared.inspect(appURL: origURL)
                _ = try WrapperBuilder.shared.buildWrapper(
                    analysis: analysis,
                    profileName: profile.name,
                    badgeColorHex: profile.badgeColorHex,
                    badgeText: profile.badgeText,
                    customArgs: profile.customArgs,
                    customEnv: profile.customEnv
                )
                rebuilt.append("\(profile.appName) (\(profile.name))")
            } catch {
                failed.append("\(profile.appName) (\(profile.name)): \(error.localizedDescription)")
            }
        }

        return (rebuilt, failed)
    }

    // MARK: - CLI Profiles Management

    public func addCLIProfile(_ profile: CLIProfile) {
        cliProfiles.removeAll { $0.id == profile.id }
        cliProfiles.append(profile)
        saveCLIProfiles()
    }

    public func deleteCLIProfile(id: UUID, deleteData: Bool) throws {
        guard let profile = cliProfiles.first(where: { $0.id == id }) else { return }

        let fileManager = FileManager.default

        // 1. Delete wrapper script
        let scriptURL = URL(fileURLWithPath: profile.wrapperScriptPath)
        if fileManager.fileExists(atPath: scriptURL.path) {
            try fileManager.removeItem(at: scriptURL)
        }

        // 2. Conditionally delete profile data
        if deleteData {
            let dataURL = URL(fileURLWithPath: profile.profileDirectory)
            if fileManager.fileExists(atPath: dataURL.path) {
                try fileManager.removeItem(at: dataURL)
            }
        }

        cliProfiles.removeAll { $0.id == id }
        saveCLIProfiles()
    }

    public func launchCLIInTerminal(_ profile: CLIProfile) {
        let command = profile.wrapperScriptPath
        let script = "tell application \"Terminal\" to do script \"\(command)\""
        if let appleScript = NSAppleScript(source: script) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
        }

        if let idx = cliProfiles.firstIndex(where: { $0.id == profile.id }) {
            cliProfiles[idx].lastLaunchedAt = Date()
            saveCLIProfiles()
        }
    }

    // MARK: - Utilities

    public func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openFolder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}
