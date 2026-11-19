import SwiftUI
import ServiceManagement
import TwinlyCore

struct SettingsView: View {
    var body: some View {
        Form {
            SoftwareUpdateSection()
            GeneralSettings()
            StorageSettings()
        }
        .formStyle(.grouped)
    }
}

struct SoftwareUpdateSection: View {
    @ObservedObject private var updater = UpdateChecker.shared

    private var isBusy: Bool {
        switch updater.status {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private var statusText: String {
        switch updater.status {
        case .checking: return "Checking for updates…"
        case .available(let r): return "Twinly \(r.tagName) is available!"
        case .downloading(let p): return p
        case .installing: return "Installing…"
        case .error(let m): return m
        case .upToDate: return "Up to date" + checkedSuffix
        case .idle:
            if let r = updater.latestAvailableRelease { return "Twinly \(r.tagName) is available!" }
            return updater.lastCheckedAt == nil ? "Not checked yet" : "Last checked" + checkedSuffix.replacingOccurrences(of: " · checked", with: "")
        }
    }

    private var checkedSuffix: String {
        guard let d = updater.lastCheckedAt else { return "" }
        return " · checked " + d.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        Section("Software Update") {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Twinly \(updater.currentVersion)").font(.headline)
                    Text(statusText).font(.callout)
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                }
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
                Button("Check for Updates") { updater.checkForUpdates(userInitiated: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
            }

            if let release = updater.latestAvailableRelease {
                VStack(alignment: .leading, spacing: 8) {
                    if !release.body.isEmpty {
                        Text(release.body)
                            .font(.callout).foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                    HStack {
                        Button("Install Update & Relaunch") { updater.downloadAndInstall(release) }
                            .buttonStyle(.borderedProminent).tint(.blue)
                            .disabled(isBusy)
                        if let url = URL(string: release.htmlURL) {
                            Link("Release Notes on GitHub", destination: url)
                        }
                    }
                }
            }

            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.autoCheckForUpdates }, set: { updater.autoCheckForUpdates = $0 }))
            Toggle("Automatically download and install updates", isOn: Binding(
                get: { updater.autoInstallUpdates }, set: { updater.autoInstallUpdates = $0 }))
        }
    }

    private var isError: Bool {
        if case .error = updater.status { return true }
        return false
    }
}

struct GeneralSettings: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var launchAtLogin = false
    @State private var loginError = false
    @State private var loaded = false

    var body: some View {
        Section("General") {
            Group {
                Toggle("Open Twinly at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        guard loaded else { return }
                        apply(newValue)
                    }
                if loginError {
                    InlineError(text: "macOS didn't allow this. Move Twinly to the Applications folder and try again.")
                }
                Toggle("Show Twinly in the menu bar", isOn: $showMenuBarIcon)
            }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            DispatchQueue.main.async { loaded = true }
        }
    }

    private func apply(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = false
        } catch {
            loginError = true
            loaded = false
            launchAtLogin = !enable
            DispatchQueue.main.async { loaded = true }
        }
    }
}

struct StorageSettings: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @State private var result: RepairResult?

    private func abbreviated(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

    var body: some View {
        Group {
            Section("Storage & Maintenance") {
                folderRow("Shortcuts", WrapperBuilder.defaultApplicationsDir)
                folderRow("Profile data", store.baseStorageDir)
                folderRow("Commands", CLIWrapperBuilder.defaultBinDir)
            }

            Section {
                HStack {
                    Button {
                        result = nil
                        ui.repairAll { result = $0 }
                    } label: {
                        HStack(spacing: 6) {
                            if ui.isRepairing { ProgressView().controlSize(.small) }
                            Text(ui.isRepairing ? "Repairing…" : "Repair All Shortcuts…")
                        }
                    }
                    .disabled(ui.isRepairing || store.profiles.isEmpty)
                    Spacer()
                }
                Text("Rebuilds every shortcut, for example after moving an app or updating Twinly. Logins and data are kept.")
                    .font(.caption).foregroundStyle(.secondary)

                if let result = result {
                    if !result.repaired.isEmpty {
                        Label("Repaired \(result.repaired.count) shortcut\(result.repaired.count == 1 ? "" : "s"). Logins and data were kept.",
                              systemImage: "checkmark.circle.fill")
                            .font(.callout).foregroundStyle(.green)
                    }
                    if !result.failed.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("\(result.failed.count) couldn't be repaired:", systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.orange)
                            ForEach(result.failed, id: \.self) { line in
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func folderRow(_ title: String, _ url: URL) -> some View {
        LabeledContent(title) {
            HStack {
                Text(abbreviated(url))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    store.openFolder(path: url.path)
                }
            }
        }
    }
}
