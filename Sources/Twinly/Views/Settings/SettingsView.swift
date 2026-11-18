import SwiftUI
import ServiceManagement
import TwinlyCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 480)
    }
}

struct GeneralSettings: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var launchAtLogin = false
    @State private var loginError = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
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
        .formStyle(.grouped)
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
        Form {
            Section {
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
        .formStyle(.grouped)
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
