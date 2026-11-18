import SwiftUI
import TwinlyCore

struct MainContentView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
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
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch ui.section {
            case .apps:
                AppsListView()
                    .navigationTitle("Apps")
            case .commandLine:
                CommandLineListView()
                    .navigationTitle("Command Line")
            case .howItWorks:
                HowItWorksView()
                    .navigationTitle("How It Works")
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
        .alert(
            ui.alert?.title ?? "",
            isPresented: Binding(get: { ui.alert != nil }, set: { if !$0 { ui.alert = nil } }),
            presenting: ui.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
        .onAppear { surfaceLoadError() }
        .onChange(of: store.loadError) { _ in surfaceLoadError() }
    }

    private var sidebarSelection: Binding<SidebarSection?> {
        Binding(get: { ui.section }, set: { if let value = $0 { ui.section = value } })
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
