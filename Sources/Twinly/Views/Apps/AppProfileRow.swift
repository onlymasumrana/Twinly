import SwiftUI
import TwinlyCore

struct AppProfileRow: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var monitor: RunningMonitor
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let profile: Profile
    @State private var hovering = false

    private var isSelected: Bool { ui.selection.contains(profile.id) }
    private var missing: Bool { ProfileStatus.isOriginalMissing(profile) }

    var body: some View {
        HStack(spacing: 12) {
            BadgedIcon(appPath: profile.originalAppPath, hex: profile.badgeColorHex, text: profile.badgeText, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(profile.appName)
                    StrategyChip(strategy: profile.strategy)
                    statusView
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Open") { ui.open(profile) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(missing)
                .opacity(hovering || isSelected || voiceOver ? 1 : 0)

            Menu {
                AppProfileMenuItems(ids: [profile.id])
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering || isSelected || voiceOver ? 1 : 0)
            .accessibilityLabel("More actions for \(profile.name)")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusView: some View {
        if missing {
            StatusLine(kind: .missing(
                help: "“\(profile.appName)” was moved or deleted from \(profile.originalAppPath).",
                label: "App not found"))
        } else if monitor.isRunning(profile) {
            StatusLine(kind: .running)
        } else {
            StatusLine(kind: .lastOpened(ProfileStatus.lastOpened(profile)))
        }
    }
}
