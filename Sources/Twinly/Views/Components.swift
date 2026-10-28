import SwiftUI
import TwinlyCore

public struct StrategyBadgeView: View {
    public let strategy: AppStrategy

    public init(strategy: AppStrategy) {
        self.strategy = strategy
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            Text(strategy.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(backgroundColor.opacity(0.15))
        .foregroundColor(backgroundColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch strategy {
        case .electronChromium: return "bolt.horizontal.fill"
        case .genericNonSandboxed: return "app.fill"
        case .sandboxedUnsupported: return "exclamationmark.triangle.fill"
        }
    }

    private var backgroundColor: Color {
        switch strategy {
        case .electronChromium: return .purple
        case .genericNonSandboxed: return .blue
        case .sandboxedUnsupported: return .red
        }
    }
}

public struct BadgedIconPreviewView: View {
    public let baseImage: NSImage
    public let badgeColorHex: String
    public let badgeText: String
    public let size: CGFloat

    public init(baseImage: NSImage, badgeColorHex: String, badgeText: String, size: CGFloat = 64) {
        self.baseImage = baseImage
        self.badgeColorHex = badgeColorHex
        self.badgeText = badgeText
        self.size = size
    }

    public var body: some View {
        let nsColor = NSColor(hex: badgeColorHex) ?? .systemBlue
        let badged = IconBadgeGenerator.shared.createBadgedImage(
            baseImage: baseImage,
            badgeColor: nsColor,
            badgeText: badgeText,
            targetSize: CGSize(width: size * 2, height: size * 2)
        )

        Image(nsImage: badged)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}
