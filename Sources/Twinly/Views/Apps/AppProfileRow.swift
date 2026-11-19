import SwiftUI
import TwinlyCore

struct AppProfileRow: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var monitor: RunningMonitor
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let profile: Profile
    @State private var hovering = false
    @State private var menuHovered = false

    private var isSelected: Bool { ui.selection.contains(profile.id) }
    private var showOpen: Bool { hovering || isSelected || voiceOver }
    private var missing: Bool { ProfileStatus.isOriginalMissing(profile) }

    var body: some View {
        HStack(spacing: 12) {
            BadgedIcon(appPath: profile.originalAppPath, hex: profile.badgeColorHex, text: profile.badgeText, size: 40)
                .scaleEffect(hovering ? 1.05 : 1.0)
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: hovering)

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
                .opacity(showOpen ? 1 : 0)
                .offset(x: showOpen ? 0 : 5)
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: showOpen)

            Menu {
                AppProfileMenuItems(ids: [profile.id])
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(menuHovered ? Color.primary : Color.secondary)
                    .scaleEffect(menuHovered ? 1.12 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: menuHovered)
                    .onHover { menuHovered = $0 }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(showOpen ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: showOpen)
            .accessibilityLabel("More actions for \(profile.name)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.15)) { hovering = hover }
        }
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
