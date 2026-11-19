import SwiftUI
import AppKit
import TwinlyCore

enum SidebarSection: Hashable {
    case apps, commandLine, howItWorks, settings
}

enum SheetRoute: Identifiable {
    case newApp(prefill: URL?)
    case editApp(Profile)
    case newCLI(template: CLIProfile?)
    case editCLI(CLIProfile)

    var id: String {
        switch self {
        case .newApp: return "newApp"
        case .editApp(let p): return "editApp-\(p.id)"
        case .newCLI: return "newCLI"
        case .editCLI(let c): return "editCLI-\(c.id)"
        }
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

enum DeleteRequest: Identifiable {
    case apps([Profile])
    case cli([CLIProfile])

    var id: String {
        switch self {
        case .apps(let p): return "apps-" + p.map { $0.id.uuidString }.joined()
        case .cli(let c): return "cli-" + c.map { $0.id.uuidString }.joined()
        }
    }
}

/// Shared UI state plus the actions that menus, toolbars and context menus all trigger.
final class UIState: ObservableObject {
    let store: ProfileStore

    @Published var section: SidebarSection = .apps
    @Published var showSidebar: Bool = true
    @Published var sheet: SheetRoute?
    @Published var selection: Set<UUID> = []
    @Published var cliSelection: Set<UUID> = []
    @Published var alert: AlertItem?
    @Published var pendingDelete: DeleteRequest?
    @Published var isRepairing = false
    @Published var pendingReset: Profile?

    init(store: ProfileStore) {
        self.store = store
    }

    // MARK: Selection helpers

    var selectedApps: [Profile] { store.profiles.filter { selection.contains($0.id) } }
    var selectedCLIs: [CLIProfile] { store.cliProfiles.filter { cliSelection.contains($0.id) } }

    var hasSelection: Bool {
        switch section {
        case .apps: return !selection.isEmpty
        case .commandLine: return !cliSelection.isEmpty
        case .howItWorks, .settings: return false
        }
    }

    func show(error: Error, title: String) {
        alert = AlertItem(title: title, message: error.localizedDescription)
    }

    // MARK: App profile actions

    func open(_ profile: Profile) {
        store.launchProfile(profile) { [weak self] error in
            if let error = error {
                self?.alert = AlertItem(title: "Couldn't Open “\(profile.appName) (\(profile.name))”", message: error.localizedDescription)
            }
        }
    }

    func open(ids: Set<UUID>) {
        store.profiles.filter { ids.contains($0.id) }.forEach(open)
    }

    func stop(_ profile: Profile) { store.stopProfile(profile) }

    func requestReset(_ profile: Profile) { pendingReset = profile }

    func performReset(_ profile: Profile) {
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async {
            do { try store.resetProfileData(id: profile.id) }
            catch { DispatchQueue.main.async { self.show(error: error, title: "Couldn't Reset “\(profile.appName) (\(profile.name))”") } }
        }
    }

    func edit(_ profile: Profile) { sheet = .editApp(profile) }

    func duplicate(_ profile: Profile) {
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let copy = try store.duplicateProfile(profile)
                DispatchQueue.main.async { self.selection = [copy.id] }
            } catch {
                DispatchQueue.main.async {
                    self.show(error: error, title: "Couldn't Duplicate “\(profile.appName) (\(profile.name))”")
                }
            }
        }
    }

    func showShortcut(_ profile: Profile) {
        guard FileManager.default.fileExists(atPath: profile.wrapperAppPath) else {
            alert = AlertItem(title: "Shortcut Missing", message: "This shortcut is missing. Choose Repair All Shortcuts in Settings.")
            return
        }
        store.revealInFinder(path: profile.wrapperAppPath)
    }

    func showData(_ profile: Profile) {
        try? FileManager.default.createDirectory(atPath: profile.profileDirectory, withIntermediateDirectories: true)
        store.openFolder(path: profile.profileDirectory)
    }

    // MARK: Command-line actions

    func openInTerminal(_ cli: CLIProfile) {
        store.launchCLIInTerminal(cli) { [weak self] error in
            if let error = error {
                self?.alert = AlertItem(title: "Couldn't Open “\(cli.commandName)”", message: error.localizedDescription)
            }
        }
    }

    func showConfigFolder(_ cli: CLIProfile) {
        try? FileManager.default.createDirectory(atPath: cli.profileDirectory, withIntermediateDirectories: true)
        store.openFolder(path: cli.profileDirectory)
    }

    func showScript(_ cli: CLIProfile) {
        guard FileManager.default.fileExists(atPath: cli.wrapperScriptPath) else {
            alert = AlertItem(title: "Script Missing", message: "\(cli.wrapperScriptPath) no longer exists.")
            return
        }
        store.revealInFinder(path: cli.wrapperScriptPath)
    }

    // MARK: Delete

    func requestDelete(apps: [Profile]) { if !apps.isEmpty { pendingDelete = .apps(apps) } }
    func requestDelete(cli: [CLIProfile]) { if !cli.isEmpty { pendingDelete = .cli(cli) } }

    func performDelete(_ request: DeleteRequest, deleteData: Bool) {
        var failures: [String] = []
        switch request {
        case .apps(let profiles):
            for p in profiles {
                do { try store.deleteProfile(id: p.id, deleteData: deleteData) }
                catch { failures.append("\(p.appName) (\(p.name)): \(error.localizedDescription)") }
                selection.remove(p.id)
            }
        case .cli(let list):
            for c in list {
                do { try store.deleteCLIProfile(id: c.id, deleteData: deleteData) }
                catch { failures.append("\(c.commandName): \(error.localizedDescription)") }
                cliSelection.remove(c.id)
            }
        }
        if !failures.isEmpty {
            alert = AlertItem(title: "Couldn't Delete Everything", message: failures.joined(separator: "\n"))
        }
    }

    // MARK: Menu-driven actions on the current selection

    func openSelected() {
        switch section {
        case .apps: open(ids: selection)
        case .commandLine: selectedCLIs.forEach(openInTerminal)
        case .howItWorks, .settings: break
        }
    }

    func editSelected() {
        switch section {
        case .apps: if let p = selectedApps.first { edit(p) }
        case .commandLine: if let c = selectedCLIs.first { sheet = .editCLI(c) }
        case .howItWorks, .settings: break
        }
    }

    func duplicateSelected() {
        switch section {
        case .apps: selectedApps.forEach(duplicate)
        case .commandLine: if let c = selectedCLIs.first { sheet = .newCLI(template: c) }
        case .howItWorks, .settings: break
        }
    }

    func showSelectedInFinder() {
        switch section {
        case .apps: selectedApps.forEach(showShortcut)
        case .commandLine: selectedCLIs.forEach(showScript)
        case .howItWorks, .settings: break
        }
    }

    func deleteSelected() {
        switch section {
        case .apps: requestDelete(apps: selectedApps)
        case .commandLine: requestDelete(cli: selectedCLIs)
        case .howItWorks, .settings: break
        }
    }

    // MARK: Repair

    /// Runs Repair All Shortcuts in the background. `completion` runs on the main thread.
    func repairAll(completion: ((RepairResult) -> Void)? = nil) {
        guard !isRepairing else { return }
        isRepairing = true
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async {
            let result = store.rebuildAllWrappers()
            DispatchQueue.main.async {
                self.isRepairing = false
                if let completion = completion {
                    completion(result)
                } else {
                    self.alert = Self.alert(for: result)
                }
            }
        }
    }

    static func alert(for result: RepairResult) -> AlertItem {
        var lines: [String] = []
        if !result.repaired.isEmpty {
            lines.append("Repaired \(result.repaired.count) shortcut\(result.repaired.count == 1 ? "" : "s"). Logins and data were kept.")
        }
        if !result.failed.isEmpty {
            lines.append("\(result.failed.count) couldn't be repaired:")
            lines += result.failed
        }
        if lines.isEmpty { lines = ["There are no shortcuts to repair."] }
        return AlertItem(title: result.failed.isEmpty ? "Shortcuts Repaired" : "Repair Finished", message: lines.joined(separator: "\n"))
    }
}

/// Tracks which Chromium/Electron profiles are currently running.
final class RunningMonitor: ObservableObject {
    @Published private(set) var running: Set<UUID> = []
    private let store: ProfileStore
    private var observers: [NSObjectProtocol] = []

    init(store: ProfileStore) {
        self.store = store
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.refresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
        refresh()
    }

    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) } }

    func refresh() {
        let profiles = store.profiles
        DispatchQueue.global(qos: .utility).async {
            let ids = Set(profiles.filter { ProfileStatus.isRunning($0) }.map(\.id))
            DispatchQueue.main.async {
                if ids != self.running { self.running = ids }
            }
        }
    }

    func isRunning(_ profile: Profile) -> Bool { running.contains(profile.id) }
}
