import SwiftUI
import TwinlyCore

struct AppsListView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @State private var search = ""
    @State private var isDropTargeted = false
    @State private var quickAdd: [InstalledApp] = []

    private var filtered: [Profile] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.profiles }
        return store.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.appName.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        Group {
            if store.profiles.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "No Results", message: "No profiles match “\(search)”.")
            } else {
                list
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ui.sheet = .newApp(prefill: nil)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                        Text("Add App")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .help("Add App Profile (⌘N)")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            AppPicker.loadApp(from: providers) { url in ui.sheet = .newApp(prefill: url) }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.06))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { quickAdd = InstalledApp.load() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(store.profiles.count) \(store.profiles.count == 1 ? "profile" : "profiles") · Drop any app here to create another")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    ui.sheet = .newApp(prefill: nil)
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("New App Profile (⌘N)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            List(selection: $ui.selection) {
                ForEach(filtered) { profile in
                    AppProfileRow(profile: profile)
                        .tag(profile.id)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .contextMenu(forSelectionType: UUID.self) { ids in
                AppProfileMenuItems(ids: ids)
            } primaryAction: { ids in
                ui.open(ids: ids)
            }
            .onDeleteCommand { ui.deleteSelected() }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "square.on.square",
            title: "Run two copies of any app",
            message: "Each profile gets its own login, settings and data. Works with Slack, Discord, Chrome, VS Code and more."
        ) {
            VStack(spacing: 10) {
                Button {
                    if let url = AppPicker.chooseApp() { ui.sheet = .newApp(prefill: url) }
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("or drop an app here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !quickAdd.isEmpty {
                    HStack(spacing: 8) {
                        Text("Quick add:").font(.callout).foregroundStyle(.secondary)
                        QuickAddRow(apps: quickAdd) { url in ui.sheet = .newApp(prefill: url) }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

/// Shared by the list's context menu, the row's ⋯ menu.
struct AppProfileMenuItems: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    let ids: Set<UUID>

    private var profiles: [Profile] { store.profiles.filter { ids.contains($0.id) } }

    var body: some View {
        if let first = profiles.first {
            let single = profiles.count == 1
            Button("Open") { ui.open(ids: ids) }
            if single {
                Button("Edit…") { ui.edit(first) }
            }
            Button("Duplicate") { profiles.forEach(ui.duplicate) }
            Divider()
            if single {
                Button("Show Shortcut in Finder") { ui.showShortcut(first) }
                Button("Show Data Folder") { ui.showData(first) }
                Divider()
            }
            Button("Delete…", role: .destructive) { ui.requestDelete(apps: profiles) }
        }
    }
}
