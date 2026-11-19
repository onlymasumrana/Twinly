import SwiftUI
import TwinlyCore

struct MainContentView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var bannerDismissed = false
    @State private var loadErrorAlert: String?

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Library") {
                    Label("Apps", systemImage: "square.on.square")
                        .badge(store.profiles.count)
                        .tag(SidebarSection.apps)
                    Label("Command Line", systemImage: "terminal")
                        .badge(store.cliProfiles.count)
                        .tag(SidebarSection.commandLine)
                }
                Section("Help") {
                    Label("How It Works", systemImage: "questionmark.circle")
                        .tag(SidebarSection.howItWorks)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.5)
                    Button {
                        ui.section = .settings
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape")
                                .font(.body)
                                .foregroundStyle(ui.section == .settings ? Color.accentColor : .secondary)
                            Text("Settings")
                                .font(.body.weight(ui.section == .settings ? .medium : .regular))
                                .foregroundStyle(.primary)
                            Spacer()
                            if updater.latestAvailableRelease != nil {
                                Text("1")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ui.section == .settings ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let release = updater.latestAvailableRelease, !bannerDismissed, ui.section != .settings {
                    updateBanner(release)
                }
                detailContent
            }
        }
        .sheet(item: $ui.sheet) { route in
            switch route {
            case .newApp(let prefill):
                NewAppProfileSheet(prefill: prefill)
            case .editApp(let profile):
                EditProfileSheet(profile: profile)
            case .newCLI(let template):
                CLIProfileSheet(mode: .new(template: template))
            case .editCLI(let cli):
                CLIProfileSheet(mode: .edit(cli))
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { ui.pendingDelete != nil }, set: { if !$0 { ui.pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: ui.pendingDelete
        ) { request in
            switch request {
            case .apps:
                Button("Delete Profile and Data", role: .destructive) { ui.performDelete(request, deleteData: true) }
                Button("Delete Profile, Keep Data") { ui.performDelete(request, deleteData: false) }
            case .cli:
                Button("Delete Command and Config", role: .destructive) { ui.performDelete(request, deleteData: true) }
                Button("Delete Command, Keep Config") { ui.performDelete(request, deleteData: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            switch request {
            case .apps: Text("Deleting the data signs you out and erases this profile's settings. This can't be undone.")
            case .cli: Text("Deleting the config signs you out of this profile. This can't be undone.")
            }
        }
        .confirmationDialog(
            ui.pendingReset.map { "Reset “\($0.appName) (\($0.name))”?" } ?? "",
            isPresented: Binding(get: { ui.pendingReset != nil }, set: { if !$0 { ui.pendingReset = nil } }),
            titleVisibility: .visible,
            presenting: ui.pendingReset
        ) { profile in
            Button("Reset Data", role: .destructive) { ui.performReset(profile) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This signs you out and clears all data for this profile. The shortcut itself is kept.")
        }
        .alert(
            ui.alert?.title ?? "",
            isPresented: Binding(get: { ui.alert != nil }, set: { if !$0 { ui.alert = nil } }),
            presenting: ui.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
        .onAppear {
            surfaceLoadError()
            if updater.autoCheckForUpdates { updater.checkForUpdates(userInitiated: false) }
        }
        .onChange(of: store.loadError) { _ in surfaceLoadError() }
    }

    @ViewBuilder private var detailContent: some View {
        switch ui.section {
        case .apps:
            AppsListView().navigationTitle("Apps")
        case .commandLine:
            CommandLineListView().navigationTitle("Command Line")
        case .howItWorks:
            HowItWorksView().navigationTitle("How It Works")
        case .settings:
            SettingsView().navigationTitle("Settings")
        }
    }

    private func updateBanner(_ release: UpdateChecker.ReleaseInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
            Text("Twinly \(release.tagName) is available").fontWeight(.medium)
            Spacer()
            Button("Update…") { ui.section = .settings }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.blue).controlSize(.small)
            Button { bannerDismissed = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.blue)
    }

    private var sidebarSelection: Binding<SidebarSection?> {
        Binding(get: { ui.section == .settings ? nil : ui.section }, set: { if let value = $0 { ui.section = value } })
    }

    private var deleteTitle: String {
        switch ui.pendingDelete {
        case .apps(let list)?:
            return list.count == 1 ? "Delete “\(list[0].appName) (\(list[0].name))”?" : "Delete \(list.count) profiles?"
        case .cli(let list)?:
            return list.count == 1 ? "Delete “\(list[0].commandName)”?" : "Delete \(list.count) commands?"
        case nil:
            return ""
        }
    }

    private func surfaceLoadError() {
        guard let message = store.loadError, ui.alert == nil else { return }
        ui.alert = AlertItem(title: "Profiles Couldn't Be Read", message: message)
        store.loadError = nil
    }
}
