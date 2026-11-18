import SwiftUI
import TwinlyCore
import AppKit
import UniformTypeIdentifiers

enum AppPicker {
    /// Shows the open panel for choosing an application.
    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Extracts the first dropped `.app` bundle.
    static func loadApp(from providers: [NSItemProvider], completion: @escaping (URL) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let u = item as? URL { url = u }
            if let url = url, url.pathExtension.lowercased() == "app" {
                DispatchQueue.main.async { completion(url) }
            }
        }
        return true
    }
}

struct InstalledApp: Identifiable {
    let url: URL
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    static func load() -> [InstalledApp] {
        Array(KnownApps.installed().prefix(8).map(InstalledApp.init(url:)))
    }
}

struct QuickAddRow: View {
    let apps: [InstalledApp]
    let action: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            ForEach(apps) { app in
                Button {
                    action(app.url)
                } label: {
                    HStack(spacing: 4) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable().frame(width: 16, height: 16)
                        Text(app.name)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        }
    }
}
