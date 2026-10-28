import Foundation
import AppKit

public final class IconBadgeGenerator {
    public static let shared = IconBadgeGenerator()

    public init() {}

    /// Generates a badged NSImage
    public func createBadgedImage(
        baseImage: NSImage,
        badgeColor: NSColor,
        badgeText: String,
        targetSize: CGSize = CGSize(width: 512, height: 512)
    ) -> NSImage {
        let badged = NSImage(size: targetSize)
        badged.lockFocus()

        // Draw base image
        let baseRect = NSRect(origin: .zero, size: targetSize)
        baseImage.draw(in: baseRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        // Badge parameters
        let badgeDiameter = targetSize.width * 0.38
        let margin = targetSize.width * 0.04
        let badgeRect = NSRect(
            x: targetSize.width - badgeDiameter - margin,
            y: margin, // macOS bottom-left coordinate system; y: margin places it at bottom-right
            width: badgeDiameter,
            height: badgeDiameter
        )

        // Draw badge shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -targetSize.width * 0.015)
        shadow.shadowBlurRadius = targetSize.width * 0.03
        shadow.set()

        // Draw badge outer ring (white outline for contrast)
        let borderPath = NSBezierPath(ovalIn: badgeRect)
        NSColor.white.setFill()
        borderPath.fill()

        shadow.shadowColor = nil
        shadow.set()

        // Draw badge filled circle
        let inset = badgeDiameter * 0.07
        let innerRect = badgeRect.insetBy(dx: inset, dy: inset)
        let innerPath = NSBezierPath(ovalIn: innerRect)
        badgeColor.setFill()
        innerPath.fill()

        // Draw badge text / symbol
        let cleanText = badgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanText.isEmpty {
            let fontSize: CGFloat
            if cleanText.count == 1 {
                fontSize = badgeDiameter * 0.52
            } else if cleanText.count == 2 {
                fontSize = badgeDiameter * 0.42
            } else {
                fontSize = badgeDiameter * 0.32
            }

            let font = NSFont.boldSystemFont(ofSize: fontSize)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]

            let attrString = NSAttributedString(string: cleanText, attributes: attributes)
            let stringSize = attrString.size()
            let textRect = NSRect(
                x: innerRect.midX - (stringSize.width / 2),
                y: innerRect.midY - (stringSize.height / 2),
                width: stringSize.width,
                height: stringSize.height
            )
            attrString.draw(in: textRect)
        }

        badged.unlockFocus()
        return badged
    }

    /// Generates a badged `.icns` file at destinationURL
    public func generateIcns(
        baseImage: NSImage,
        badgeColor: NSColor,
        badgeText: String,
        destinationURL: URL
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconsetDir = tempDir.appendingPathComponent("icon.iconset")
        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sizes: [(name: String, pixelSize: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for entry in sizes {
            let img = createBadgedImage(
                baseImage: baseImage,
                badgeColor: badgeColor,
                badgeText: badgeText,
                targetSize: CGSize(width: entry.pixelSize, height: entry.pixelSize)
            )

            guard let tiffData = img.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                continue
            }

            let fileURL = iconsetDir.appendingPathComponent(entry.name)
            try pngData.write(to: fileURL)
        }

        // Run iconutil -c icns icon.iconset -o destinationURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconsetDir.path, "-o", destinationURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw IconGenerationError.iconutilFailed("iconutil failed with code \(process.terminationStatus): \(errorString)")
        }
    }
}

public enum IconGenerationError: LocalizedError {
    case iconutilFailed(String)
    case renderingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .iconutilFailed(let msg): return msg
        case .renderingFailed(let msg): return msg
        }
    }
}

public extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b, a: CGFloat
        if hexSanitized.count == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if hexSanitized.count == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else {
            return "#3B82F6"
        }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
