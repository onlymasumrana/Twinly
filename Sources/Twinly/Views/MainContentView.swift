import SwiftUI
import TwinlyCore

struct MainContentView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var bannerDismissed = false
    @State private var loadErrorAlert: String?

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 200)
                    .frame(width: ui.showSidebar ? 200 : 0, alignment: .trailing)
                    .clipped()
                    .allowsHitTesting(ui.showSidebar)

                if ui.showSidebar {
                    Divider()
                }

                VStack(spacing: 0) {
                    if let release = updater.latestAvailableRelease, !bannerDismissed, ui.section != .settings {
                        updateBanner(release)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    detailContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: bannerDismissed)
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.88), value: ui.showSidebar)
            .navigationTitle(sectionTitle)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                            ui.showSidebar.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help(ui.showSidebar ? "Hide Sidebar (⌃⌘S)" : "Show Sidebar (⌃⌘S)")
                    .accessibilityLabel(ui.showSidebar ? "Hide Sidebar" : "Show Sidebar")
                }
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
            AppsListView()
        case .commandLine:
            CommandLineListView()
        case .howItWorks:
            HowItWorksView()
        case .settings:
            SettingsView()
        }
    }

    private var sectionTitle: String {
        switch ui.section {
        case .apps: return "Apps"
        case .commandLine: return "Command Line"
        case .howItWorks: return "How It Works"
        case .settings: return "Settings"
        }
    }

    private func updateBanner(_ release: UpdateChecker.ReleaseInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
            Text("Twinly \(release.tagName) is available").fontWeight(.medium)
            Spacer()
            Button("Update…") { withAnimation(.easeOut(duration: 0.14)) { ui.section = .settings } }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.blue).controlSize(.small)
            Button { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { bannerDismissed = true } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.blue)
    }

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

                SidebarRow(
                    title: "Apps",
                    systemImage: "square.on.square",
                    badge: store.profiles.count > 0 ? "\(store.profiles.count)" : nil,
                    isSelected: ui.section == .apps
                ) {
                    ui.section = .apps
                }

                SidebarRow(
                    title: "Command Line",
                    systemImage: "terminal",
                    badge: store.cliProfiles.count > 0 ? "\(store.cliProfiles.count)" : nil,
                    isSelected: ui.section == .commandLine
                ) {
                    ui.section = .commandLine
                }

                Text("Help")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                SidebarRow(
                    title: "How It Works",
                    systemImage: "questionmark.circle",
                    badge: nil,
                    isSelected: ui.section == .howItWorks
                ) {
                    ui.section = .howItWorks
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)

            Spacer(minLength: 0)

            Divider()
                .opacity(0.5)

            SidebarRow(
                title: "Settings",
                systemImage: "gearshape",
                badge: updater.latestAvailableRelease != nil ? "1" : nil,
                accentBadge: true,
                isSelected: ui.section == .settings
            ) {
                withAnimation(.easeOut(duration: 0.14)) {
                    ui.section = .settings
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
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

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let badge: String?
    var accentBadge: Bool = false
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.body.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge = badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accentBadge ? .white : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(accentBadge ? Color.accentColor : Color.secondary.opacity(0.2))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.18)
                            : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hover
            }
        }
    }
}
