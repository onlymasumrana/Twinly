import SwiftUI
import TwinlyCore

@main
struct TwinlyApp: App {
    @StateObject private var store: ProfileStore
    @StateObject private var ui: UIState
    @StateObject private var monitor: RunningMonitor
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @Environment(\.openWindow) private var openWindow

    init() {
        let store = ProfileStore.shared // Initializes and loads persisted profiles.
        store.syncOutdatedClonesIfNeeded()
        _store = StateObject(wrappedValue: store)
        _ui = StateObject(wrappedValue: UIState(store: store))
        _monitor = StateObject(wrappedValue: RunningMonitor(store: store))
    }

    var body: some Scene {
        Window("Twinly", id: "main") {
            MainContentView()
                .environmentObject(store)
                .environmentObject(ui)
                .environmentObject(monitor)
                .frame(minWidth: 760, idealWidth: 900, minHeight: 500, idealHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            TwinlyCommands(ui: ui) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(ui)
                .frame(width: 540, height: 620)
        }

        MenuBarExtra("Twinly", systemImage: "square.on.square", isInserted: $showMenuBarIcon) {
            MenuBarContent(openMain: showMainWindow)
                .environmentObject(store)
                .environmentObject(ui)
                .environmentObject(monitor)
        }
        .menuBarExtraStyle(.menu)
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var monitor: RunningMonitor
    let openMain: () -> Void

    var body: some View {
        if store.profiles.isEmpty && store.cliProfiles.isEmpty {
            Text("No profiles yet")
        } else {
            if !store.profiles.isEmpty {
                Section("Apps") {
                    ForEach(store.profiles) { profile in
                        Button("\(monitor.isRunning(profile) ? "● " : "")\(profile.appName) — \(profile.name)") {
                            ui.open(profile)
                        }
                        .disabled(ProfileStatus.isOriginalMissing(profile))
                    }
                }
            }
            if !store.cliProfiles.isEmpty {
                Section("Command Line") {
                    ForEach(store.cliProfiles) { cli in
                        Button(cli.commandName) {
                            ui.openInTerminal(cli)
                        }
                    }
                }
            }
        }

        Divider()

        Button("New App Profile…") {
            openMain()
            ui.section = .apps
            ui.sheet = .newApp(prefill: nil)
        }
        Button("Open Twinly") { openMain() }
            .keyboardShortcut("0")
        Button("Show Shortcuts Folder") {
            try? FileManager.default.createDirectory(at: WrapperBuilder.defaultApplicationsDir, withIntermediateDirectories: true)
            store.openFolder(path: WrapperBuilder.defaultApplicationsDir.path)
        }

        Divider()

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
        .keyboardShortcut(",")
        Button("Quit Twinly") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
