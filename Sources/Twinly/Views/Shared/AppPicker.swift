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

    /// All installed apps: known apps first, then every other .app bundle alphabetically.
    static func loadAll() -> [InstalledApp] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let twinlyDir = home.appendingPathComponent("Applications/Twinly").standardizedFileURL.path
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]

        var discovered: [URL] = []
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                let std = item.standardizedFileURL
                if std.path == twinlyDir || item.lastPathComponent == "Twinly.app" { continue }
                if item.pathExtension.lowercased() == "app" { discovered.append(item) }
            }
        }

        var seen = Set<String>()
        var result: [InstalledApp] = []
        for url in KnownApps.installed() where seen.insert(url.path).inserted {
            result.append(InstalledApp(url: url))
        }
        let rest = discovered
            .filter { !seen.contains($0.path) }
            .sorted { $0.deletingPathExtension().lastPathComponent
                .localizedCaseInsensitiveCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending }
        for url in rest where seen.insert(url.path).inserted {
            result.append(InstalledApp(url: url))
        }
        return result
    }
}

struct AppPickerRow: View {
    let app: InstalledApp
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 28, height: 28)
                    .scaleEffect(hovering ? 1.06 : 1.0)
                Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Text("Select").font(.callout)
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .offset(x: hovering ? 0 : -4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.accentColor.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.12)) { hovering = hover }
        }
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
