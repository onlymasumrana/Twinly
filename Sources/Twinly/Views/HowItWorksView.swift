import SwiftUI
import TwinlyCore

struct HowItWorksView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        explainerRow(
                            icon: "bolt.horizontal.fill",
                            title: "Chromium-based apps",
                            subtitle: "Slack, Discord, VS Code, Chrome, Claude and more",
                            text: "Each profile gets its own data folder, so cookies, logins and settings stay separate."
                        )
                        Divider()
                        explainerRow(
                            icon: "app.fill",
                            title: "Standard apps",
                            subtitle: "Regular Mac apps",
                            text: "Each profile gets its own Library folder for settings and data."
                        )
                        Divider()
                        explainerRow(
                            icon: "terminal.fill",
                            title: "Command-line tools",
                            subtitle: "Claude Code, Codex, GitHub CLI and others",
                            text: "Twinly makes a command in ~/.local/bin that points the tool at its own config folder, then runs the real tool."
                        )
                    }
                    .padding(6)
                } label: {
                    Text("How It Works").font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        DisclosureGroup("Some apps share logins through the Keychain") {
                            note("A few Mac apps save their login in the macOS Keychain under a fixed name instead of in their data folder. Copies of those apps may share one login. Chromium browsers and Claude Code keep logins per profile.")
                        }
                        Divider()
                        DisclosureGroup("The Dock shows the original icon while running") {
                            note("While a copy runs, macOS shows the original app's icon in the Dock. The shortcut in Finder, Spotlight and Launchpad keeps your badge.")
                        }
                        Divider()
                        DisclosureGroup("App Store apps can't be copied") {
                            note("macOS locks the data of sandboxed App Store apps to one copy. Twinly detects these and tells you before you start.")
                        }
                        Divider()
                        DisclosureGroup("Each copy runs on its own") {
                            note("Because each profile has its own data folder, apps that normally allow only one window of themselves can run side by side.")
                        }
                    }
                    .padding(6)
                } label: {
                    Text("Good to Know").font(.headline)
                }

                GroupBox {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable().frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Twinly \(version)").font(.title3.weight(.semibold))
                            Text("Free and open source (MIT).")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack(spacing: 14) {
                                Link("View on GitHub", destination: URL(string: "https://github.com/onlymasumrana/Twinly")!)
                                Link("Report an Issue", destination: URL(string: "https://github.com/onlymasumrana/Twinly/issues")!)
                            }
                            .font(.callout)
                        }
                        Spacer()
                    }
                    .padding(6)
                } label: {
                    Text("About").font(.headline)
                }
            }
            .frame(maxWidth: 640)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func explainerRow(icon: String, title: String, subtitle: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                Text(text).font(.callout).padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }
}
