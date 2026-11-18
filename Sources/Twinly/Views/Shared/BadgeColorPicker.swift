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
                let selected = hex.uppercased() == preset.hex
                Button {
                    hex = preset.hex
                } label: {
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: preset.hex) ?? .systemBlue))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
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
