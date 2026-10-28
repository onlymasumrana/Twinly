import SwiftUI
import AppKit
import TwinlyCore

struct MaintenanceView: View {
    @ObservedObject var store: ProfileStore

    @State private var isRebuilding = false
    @State private var rebuildResult: (rebuilt: [String], failed: [String])?
    @State private var showResultAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Actions & Tools Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile Maintenance")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Re-sign and refresh all persistent .app shortcuts in ~/Applications/Twinly if you moved original applications or updated Twinly.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button(action: rebuildAll) {
                            if isRebuilding {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.6)
                                    Text("Rebuilding…")
                                }
                            } else {
                                Label("Rebuild All Wrappers", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRebuilding || store.profiles.isEmpty)

                        Button(action: {
                            store.openFolder(path: WrapperBuilder.defaultApplicationsDir.path)
                        }) {
                            Label("Open Shortcuts Folder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            store.openFolder(path: store.baseStorageDir.path)
                        }) {
                            Label("Open Data Storage", systemImage: "internaldrive")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let result = rebuildResult {
                        VStack(alignment: .leading, spacing: 6) {
                            if !result.rebuilt.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                    Text("Successfully rebuilt \(result.rebuilt.count) wrapper(s)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            if !result.failed.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                                    Text("Failed to rebuild \(result.failed.count) wrapper(s): \(result.failed.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

                // Architecture & How it works
                VStack(alignment: .leading, spacing: 14) {
                    Text("Architecture & How It Works")
                        .font(.title3)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 10) {
                        strategyExplainerRow(
                            icon: "bolt.horizontal.fill",
                            color: .purple,
                            title: "Electron / Chromium Apps",
                            subtitle: "Claude, Slack, Discord, VS Code, Google Chrome, Brave, Edge",
                            bodyText: "Launched with a dedicated --user-data-dir parameter. Cookies, IndexedDB, local storage, sessions, and preferences are strictly isolated."
                        )

                        Divider()

                        strategyExplainerRow(
                            icon: "app.fill",
                            color: .blue,
                            title: "Generic Non-Sandboxed Apps",
                            subtitle: "Standard macOS Cocoa / AppKit applications",
                            bodyText: "Launched with the HOME environment variable redirected to an isolated directory containing its own Library/Application Support, Library/Preferences, and Library/Caches."
                        )

                        Divider()

                        strategyExplainerRow(
                            icon: "terminal.fill",
                            color: .accentColor,
                            title: "CLI Tools",
                            subtitle: "Claude Code, Codex CLI, GitHub CLI, Custom tools",
                            bodyText: "Generates an executable shell wrapper in ~/.local/bin/ that sets the tool's isolated config environment variable (e.g. CLAUDE_CONFIG_DIR, CODEX_HOME, GH_CONFIG_DIR) and execs the real binary."
                        )
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

                // Known Limitations & FAQ
                VStack(alignment: .leading, spacing: 14) {
                    Text("Known Limitations & Notes")
                        .font(.title3)
                        .fontWeight(.semibold)

                    limitationRow(
                        title: "1. Keychain Sharing",
                        description: "Some macOS apps store authentication tokens inside the macOS Keychain with a static service name (not scoped to the profile directory). If an app relies strictly on a shared Keychain entry instead of its data folder, instances may share login credentials. Claude Code CLI and Chromium browsers maintain per-profile configuration."
                    )

                    limitationRow(
                        title: "2. Dock Icon Behavior",
                        description: "When an isolated wrapper starts, macOS launches the original app's binary. The WindowServer identifies the running process by the original bundle ID, meaning the Dock icon usually displays the original app's appearance. The wrapper shortcut in Spotlight, Launchpad, and Finder always displays your custom badged icon."
                    )

                    limitationRow(
                        title: "3. Sandboxed App Store Apps",
                        description: "Apps distributed through the Mac App Store with com.apple.security.app-sandbox cannot be cloned because macOS enforces sandbox container directories locked to the binary's bundle identifier and developer certificate. Twinly clearly detects and flags these apps."
                    )

                    limitationRow(
                        title: "4. Single-Instance Locks",
                        description: "Most apps maintain single-instance locks via Unix domain sockets or lockfiles placed inside their user data directory. Because Twinly provides a distinct data directory, both instances run concurrently without conflict."
                    )
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
            .padding()
        }
    }

    private func strategyExplainerRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        bodyText: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(bodyText)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(.top, 2)
            }
        }
    }

    private func limitationRow(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func rebuildAll() {
        isRebuilding = true
        rebuildResult = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let res = store.rebuildAllWrappers()
            DispatchQueue.main.async {
                rebuildResult = res
                isRebuilding = false
            }
        }
    }
}
