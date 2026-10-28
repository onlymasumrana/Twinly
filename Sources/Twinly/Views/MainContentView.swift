import SwiftUI
import TwinlyCore

enum NavigationTab: String, Hashable, CaseIterable {
    case guiProfiles = "App Profiles"
    case cliProfiles = "CLI Profiles"
    case maintenance = "Maintenance & Info"

    var iconName: String {
        switch self {
        case .guiProfiles: return "square.stack.3d.up.fill"
        case .cliProfiles: return "apple.terminal.fill"
        case .maintenance: return "gearshape.2.fill"
        }
    }
}

struct MainContentView: View {
    @ObservedObject var store: ProfileStore
    @State private var selectedTab: NavigationTab = .guiProfiles
    @State private var showAddSheet = false

    var body: some View {
        NavigationSplitView {
            List(NavigationTab.allCases, id: \.self, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.iconName)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case .guiProfiles:
                ProfilesListView(store: store, showAddSheet: $showAddSheet)
            case .cliProfiles:
                CLIProfilesView(store: store)
            case .maintenance:
                MaintenanceView(store: store)
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .sheet(isPresented: $showAddSheet) {
            AddProfileSheet(store: store)
        }
    }
}
