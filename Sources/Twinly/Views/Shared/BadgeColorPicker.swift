import SwiftUI
import AppKit
import TwinlyCore

struct BadgeColorPicker: View {
    @Binding var hex: String

    static let presets: [(name: String, hex: String)] = [
        ("Blue", "#3B82F6"), ("Purple", "#8B5CF6"), ("Pink", "#EC4899"), ("Red", "#EF4444"),
        ("Orange", "#F97316"), ("Amber", "#F59E0B"), ("Green", "#10B981"), ("Teal", "#06B6D4"),
        ("Indigo", "#6366F1"), ("Slate", "#64748B")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.presets, id: \.hex) { preset in
                ColorSwatchButton(preset: preset, selected: hex.uppercased() == preset.hex) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { hex = preset.hex }
                }
            }
            ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .help("Custom color")
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: hex) ?? .systemBlue) },
            set: { hex = NSColor($0).hexString }
        )
    }
}

private struct ColorSwatchButton: View {
    let preset: (name: String, hex: String)
    let selected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: NSColor(hex: preset.hex) ?? .systemBlue))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3).opacity(selected ? 1 : 0))
                .scaleEffect(isHovered ? (selected ? 1.08 : 1.18) : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: selected)
        .help(preset.name)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
