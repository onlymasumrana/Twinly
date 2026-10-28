import Foundation
import AppKit

func generateAppIcon(destinationURL: URL) throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let iconsetDir = tempDir.appendingPathComponent("icon.iconset")
    try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

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
        let size = CGFloat(entry.pixelSize)
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()

        // Background rounded square
        let rect = NSRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
        let cornerRadius = size * 0.22
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        // Gradient from Indigo to Electric Cyan
        let gradient = NSGradient(
            starting: NSColor(srgbRed: 0.38, green: 0.22, blue: 0.95, alpha: 1.0),
            ending: NSColor(srgbRed: 0.12, green: 0.65, blue: 0.98, alpha: 1.0)
        )
        gradient?.draw(in: path, angle: -45)

        // Twin layered tiles
        let tile1Rect = NSRect(x: size * 0.24, y: size * 0.30, width: size * 0.38, height: size * 0.38)
        let tile1Path = NSBezierPath(roundedRect: tile1Rect, xRadius: size * 0.08, yRadius: size * 0.08)
        NSColor.white.withAlphaComponent(0.35).setFill()
        tile1Path.fill()

        let tile2Rect = NSRect(x: size * 0.38, y: size * 0.20, width: size * 0.38, height: size * 0.38)
        let tile2Path = NSBezierPath(roundedRect: tile2Rect, xRadius: size * 0.08, yRadius: size * 0.08)
        NSColor.white.withAlphaComponent(0.95).setFill()
        tile2Path.fill()

        // Overlay symbol "T"
        let fontSize = size * 0.22
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.38, green: 0.22, blue: 0.95, alpha: 1.0)
        ]
        let attrString = NSAttributedString(string: "2", attributes: attrs)
        let stringSize = attrString.size()
        let textRect = NSRect(
            x: tile2Rect.midX - (stringSize.width / 2),
            y: tile2Rect.midY - (stringSize.height / 2),
            width: stringSize.width,
            height: stringSize.height
        )
        attrString.draw(in: textRect)

        img.unlockFocus()

        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: iconsetDir.appendingPathComponent(entry.name))
        }
    }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconsetDir.path, "-o", destinationURL.path]
    try p.run()
    p.waitUntilExit()
}

if CommandLine.arguments.count > 1 {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    try generateAppIcon(destinationURL: out)
    print("Generated app icon at \(out.path)")
}
