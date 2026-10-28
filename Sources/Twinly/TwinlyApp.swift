import SwiftUI
import TwinlyCore

@main
struct TwinlyApp: App {
    @StateObject private var store = ProfileStore.shared

    var body: some Scene {
        WindowGroup {
            MainContentView(store: store)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rebuild All Wrappers…") {
                    _ = store.rebuildAllWrappers()
                }
            }
        }

        MenuBarExtra("Twinly", systemImage: "square.2.layers.3d.top.filled") {
            VStack {
                if store.profiles.isEmpty && store.cliProfiles.isEmpty {
                    Text("No profiles configured")
                } else {
                    if !store.profiles.isEmpty {
                        Text("App Profiles").font(.caption).foregroundColor(.secondary)
                        ForEach(store.profiles) { profile in
                            Button("\(profile.appName) (\(profile.name))") {
                                store.launchProfile(profile)
                            }
                        }
                    }

                    if !store.cliProfiles.isEmpty {
                        Divider()
                        Text("CLI Profiles").font(.caption).foregroundColor(.secondary)
                        ForEach(store.cliProfiles) { cli in
                            Button(cli.commandName) {
                                store.launchCLIInTerminal(cli)
                            }
                        }
                    }
                }

                Divider()

                Button("Open Shortcuts Folder") {
                    store.openFolder(path: WrapperBuilder.defaultApplicationsDir.path)
                }

                Button("Quit Twinly") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
