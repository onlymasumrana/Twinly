import SwiftUI
import AppKit
import TwinlyCore

struct CommandLineListView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @State private var search = ""
    @State private var pathOK: Bool?
    @State private var copiedFix = false

    private var filtered: [CLIProfile] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.cliProfiles }
        return store.cliProfiles.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.commandName.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        Group {
            if store.cliProfiles.isEmpty {
                EmptyStateView(
                    symbol: "terminal",
                    title: "Separate logins for command-line tools",
                    message: "Make commands like claude-work and claude-personal, each with its own login. Works with Claude Code, Codex and GitHub CLI."
                ) {
                    Button {
                        ui.sheet = .newCLI(template: nil)
                    } label: {
                        Label("Add CLI", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else if filtered.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "No Results", message: "No profiles match “\(search)”.")
            } else {
                list
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .task { await checkPath() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(store.cliProfiles.count) \(store.cliProfiles.count == 1 ? "command" : "commands") · Runs in ~/.local/bin with isolated config")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    ui.sheet = .newCLI(template: nil)
                } label: {
                    Label("Add CLI", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("New Command-Line Profile (⇧⌘N)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            List(selection: $ui.cliSelection) {
                Section {
                    ForEach(filtered) { cli in
                        CLIProfileRow(profile: cli)
                            .tag(cli.id)
                    }
                } header: {
                    if pathOK == false { pathBanner }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .contextMenu(forSelectionType: UUID.self) { ids in
                CLIProfileMenuItems(ids: ids)
            } primaryAction: { ids in
                store.cliProfiles.filter { ids.contains($0.id) }.forEach(ui.openInTerminal)
            }
            .onDeleteCommand { ui.deleteSelected() }
        }
    }

    private var pathBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your terminal can't find Twinly commands yet")
                    .font(.body.weight(.semibold))
                Text("Add ~/.local/bin to your PATH, then open a new terminal window.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(copiedFix ? "✓ Copied" : "Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(CLIWrapperBuilder.shared.shellPathFixCommand(), forType: .string)
                copiedFix = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedFix = false }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .textCase(nil)
        .padding(.bottom, 6)
    }

    private func checkPath() async {
        guard pathOK == nil else { return }
        let ok = await Task.detached(priority: .utility) { CLIWrapperBuilder.shared.isLocalBinInPath() }.value
        pathOK = ok
    }
}

struct CLIProfileMenuItems: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    let ids: Set<UUID>

    private var profiles: [CLIProfile] { store.cliProfiles.filter { ids.contains($0.id) } }

    var body: some View {
        if let first = profiles.first {
            let single = profiles.count == 1
            Button("Open in Terminal") { profiles.forEach(ui.openInTerminal) }
            if single {
                Button("Edit…") { ui.sheet = .editCLI(first) }
                Button("Copy Command Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(first.commandName, forType: .string)
                }
                Divider()
                Button("Show Config Folder") { ui.showConfigFolder(first) }
                Button("Show Script in Finder") { ui.showScript(first) }
                Divider()
            }
            Button("Delete…", role: .destructive) { ui.requestDelete(cli: profiles) }
        }
    }
}
