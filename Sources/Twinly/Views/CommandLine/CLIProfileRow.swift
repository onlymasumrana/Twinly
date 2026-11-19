import SwiftUI
import TwinlyCore

struct CLIProfileRow: View {
    @EnvironmentObject var ui: UIState
    let profile: CLIProfile
    @State private var hovered = false

    private var toolMissing: Bool { !FileManager.default.fileExists(atPath: profile.realBinaryPath) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.12)))
                .scaleEffect(hovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: hovered)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.commandName)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                    Text("\(profile.name) · \(profile.preset.shortName)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                HStack(spacing: 6) {
                    Text(profile.configEnvVar)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    if toolMissing {
                        StatusLine(kind: .missing(help: "\(profile.realBinaryPath) no longer exists.", label: "Tool not found"))
                    } else {
                        Text("runs \(profile.realBinaryPath)")
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(profile.realBinaryPath)
                    }
                    StatusLine(kind: .lastOpened(profile.lastLaunchedAt))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            CopyButton(text: profile.commandName, help: "Copy “\(profile.commandName)”")
            Button("Open in Terminal") { ui.openInTerminal(profile) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hover }
        }
    }
}
