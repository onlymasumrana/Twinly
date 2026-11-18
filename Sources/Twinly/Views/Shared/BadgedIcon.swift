import SwiftUI
import AppKit
import TwinlyCore

final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(appPath: String, hex: String, text: String, size: CGFloat) -> NSImage {
        let key = "\(appPath)|\(hex)|\(text)|\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let base = NSWorkspace.shared.icon(forFile: appPath)
        let badged = IconBadgeGenerator.shared.createBadgedImage(
            baseImage: base,
            badgeColor: NSColor(hex: hex) ?? .systemBlue,
            badgeText: text,
            targetSize: CGSize(width: size * 2, height: size * 2)
        )
        cache.setObject(badged, forKey: key)
        return badged
    }
}

struct BadgedIcon: View {
    let appPath: String
    let hex: String
    let text: String
    var size: CGFloat = 40

    var body: some View {
        Image(nsImage: IconCache.shared.image(appPath: appPath, hex: hex, text: text, size: size))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
