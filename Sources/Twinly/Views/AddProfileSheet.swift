import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TwinlyCore

struct AddProfileSheet: View {
    @ObservedObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAppURL: URL?
    @State private var analysis: AppAnalysis?
    @State private var isInspecting = false
    @State private var errorMessage: String?

    @State private var profileName: String = "Profile 2"
    @State private var badgeText: String = "2"
    @State private var badgeColorHex: String = "#3B82F6"
    @State private var customArgsString: String = ""
    @State private var showAdvanced: Bool = false
    @State private var customEnvString: String = ""

    @State private var isCreating = false
    @State private var isTargetedForDrop = false

    let presetColors = [
        "#3B82F6", // Blue
        "#8B5CF6", // Purple
        "#EC4899", // Pink
        "#EF4444", // Red
        "#F97316", // Orange
        "#F59E0B", // Amber
        "#10B981", // Green
        "#06B6D4", // Teal
        "#6366F1", // Indigo
        "#64748B"  // Slate
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add App Profile")
                        .font(.headline)
                    Text("Create an isolated clone with independent login, data and settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // App Selection Zone
                    if let analysis = analysis {
                        appAnalysisCard(analysis)
                    } else {
                        dropOrBrowseZone
                    }

                    if let analysis = analysis, analysis.strategy != .sandboxedUnsupported {
                        profileConfigurationSection(analysis)
                    }

                    if let err = errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                if analysis != nil {
                    Button("Choose Different App") {
                        analysis = nil
                        selectedAppURL = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(action: createProfile) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 50)
                    } else {
                        Text("Create Profile")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(analysis == nil || analysis?.strategy == .sandboxedUnsupported || profileName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 600)
    }

    private var dropOrBrowseZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 40))
                .foregroundColor(isTargetedForDrop ? .accentColor : .secondary)

            Text("Drag & drop an application here")
                .font(.headline)

            Text("Or choose an app from your Applications folder")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Browse Application…") {
                selectAppWithPanel()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, url.pathExtension == "app" {
                    DispatchQueue.main.async {
                        inspectApp(url: url)
                    }
                }
            }
            return true
        }
    }

    private func appAnalysisCard(_ analysis: AppAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                BadgedIconPreviewView(
                    baseImage: getAppIcon(analysis),
                    badgeColorHex: badgeColorHex,
                    badgeText: badgeText,
                    size: 56
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.appName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(analysis.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    StrategyBadgeView(strategy: analysis.strategy)
                }
                Spacer()
            }

            // Strategy description or Sandbox warning
            if analysis.strategy == .sandboxedUnsupported {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundColor(.red)
                        Text("Sandboxed App Not Supported")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    Text(analysis.explanation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let warning = analysis.warning {
                        Text(warning)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Isolation Strategy")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(analysis.explanation)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func profileConfigurationSection(_ analysis: AppAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Profile Name")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                TextField("e.g. Work, Personal, Client X", text: $profileName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Badge Color & Text")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(presetColors, id: \.self) { colorHex in
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: colorHex) ?? .blue))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: badgeColorHex == colorHex ? 2.5 : 0)
                            )
                            .shadow(radius: badgeColorHex == colorHex ? 2 : 0)
                            .onTapGesture {
                                badgeColorHex = colorHex
                            }
                    }

                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: NSColor(hex: badgeColorHex) ?? .blue) },
                        set: { newColor in
                            if let ns = NSColor(newColor).usingColorSpace(.sRGB) {
                                badgeColorHex = ns.hexString
                            }
                        }
                    ))
                    .labelsHidden()
                }

                HStack {
                    Text("Badge Letter/Symbol:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("2", text: $badgeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }

            // Advanced options toggle
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extra Command Line Arguments (space separated)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. --incognito --disable-features=...", text: $customArgsString)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Environment Variables (KEY=VALUE per line)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $customEnvString)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 60)
                            .border(Color.secondary.opacity(0.2))
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Advanced Isolation Options")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func getAppIcon(_ analysis: AppAnalysis) -> NSImage {
        if let iconURL = analysis.iconURL, let img = NSImage(contentsOf: iconURL) {
            return img
        }
        return NSWorkspace.shared.icon(forFile: analysis.appURL.path)
    }

    private func selectAppWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            inspectApp(url: url)
        }
    }

    private func inspectApp(url: URL) {
        selectedAppURL = url
        isInspecting = true
        errorMessage = nil

        do {
            let res = try AppInspector.shared.inspect(appURL: url)
            self.analysis = res
            // Auto name profile
            let count = store.profiles.filter { $0.originalAppPath == url.path }.count
            self.profileName = count > 0 ? "Profile \(count + 1)" : "Work"
            self.badgeText = count > 0 ? "\(count + 1)" : "W"
            if count < presetColors.count {
                self.badgeColorHex = presetColors[count % presetColors.count]
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.analysis = nil
        }
        isInspecting = false
    }

    private func createProfile() {
        guard let analysis = analysis else { return }
        isCreating = true
        errorMessage = nil

        let args = customArgsString
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        var env = [String: String]()
        for line in customEnvString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let k = String(trimmed[..<eqIdx])
            let v = String(trimmed[trimmed.index(after: eqIdx)...])
            env[k] = v
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let profile = try WrapperBuilder.shared.buildWrapper(
                    analysis: analysis,
                    profileName: profileName,
                    badgeColorHex: badgeColorHex,
                    badgeText: badgeText,
                    customArgs: args,
                    customEnv: env
                )

                DispatchQueue.main.async {
                    store.addProfile(profile)
                    isCreating = false
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
