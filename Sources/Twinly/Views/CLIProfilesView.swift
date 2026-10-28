import SwiftUI
import AppKit
import TwinlyCore

struct CLIProfilesView: View {
    @ObservedObject var store: ProfileStore
    @State private var showAddSheet = false
    @State private var cliToDelete: CLIProfile?
    @State private var showDeleteConfirmation = false
    @State private var copiedFixCommand = false
    @State private var copiedCommandName: String?

    var isPathConfigured: Bool {
        CLIWrapperBuilder.shared.isLocalBinInPath()
    }

    var body: some View {
        VStack(spacing: 0) {
            // PATH Warning banner if ~/.local/bin is not in PATH
            if !isPathConfigured {
                pathWarningBanner
            }

            // Toolbar / Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CLI Profiles")
                        .font(.headline)
                    Text("Isolate CLI tools like Claude Code, Codex CLI, and GitHub CLI with custom config directories.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showAddSheet = true }) {
                    Label("Add CLI Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if store.cliProfiles.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.cliProfiles) { profile in
                            cliCard(profile)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCLIProfileSheet(store: store)
        }
        .confirmationDialog(
            "Delete CLI Profile",
            isPresented: $showDeleteConfirmation,
            presenting: cliToDelete
        ) { profile in
            Button("Delete Wrapper & Config Data", role: .destructive) {
                try? store.deleteCLIProfile(id: profile.id, deleteData: true)
            }
            Button("Delete Wrapper Only (Keep Data)") {
                try? store.deleteCLIProfile(id: profile.id, deleteData: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("Delete wrapper script for '\(profile.commandName)'?\nYou can choose whether to preserve the configuration folder.")
        }
    }

    private var pathWarningBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text("~/.local/bin is not in your current PATH")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("To run created CLI profiles directly from any terminal window, add ~/.local/bin to your shell config.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: copyPathFix) {
                HStack(spacing: 4) {
                    Image(systemName: copiedFixCommand ? "checkmark" : "doc.on.doc")
                    Text(copiedFixCommand ? "Copied!" : "Copy Fix Command")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No CLI Profiles Yet")
                .font(.title2)
                .fontWeight(.medium)
            Text("Set up distinct configurations for Claude Code (claude-work, claude-personal), Codex CLI, or gh.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button("Add First CLI Profile") {
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cliCard(_ profile: CLIProfile) -> some View {
        HStack(spacing: 14) {
            // Terminal icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "apple.terminal.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.commandName)
                        .font(.system(.headline, design: .monospaced))
                    Text("(\(profile.name))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Text("Env: \(profile.configEnvVar)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)

                    Text("Target: \(URL(fileURLWithPath: profile.realBinaryPath).lastPathComponent)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let last = profile.lastLaunchedAt {
                        Text("• Launched \(relativeTime(last))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(profile.commandName, forType: .string)
                    copiedCommandName = profile.commandName
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedCommandName == profile.commandName { copiedCommandName = nil }
                    }
                }) {
                    Image(systemName: copiedCommandName == profile.commandName ? "checkmark" : "doc.on.doc")
                }
                .help("Copy command name")
                .buttonStyle(.bordered)

                Button("Run in Terminal") {
                    store.launchCLIInTerminal(profile)
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    Button("Open Config Directory") {
                        store.openFolder(path: profile.profileDirectory)
                    }
                    Button("Reveal Wrapper Script") {
                        store.revealInFinder(path: profile.wrapperScriptPath)
                    }
                    Divider()
                    Button(role: .destructive, action: {
                        cliToDelete = profile
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Profile…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func copyPathFix() {
        let cmd = CLIWrapperBuilder.shared.shellPathFixCommand()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        copiedFixCommand = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            copiedFixCommand = false
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct AddCLIProfileSheet: View {
    @ObservedObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var preset: CLIPreset = .claudeCode
    @State private var profileName: String = "Work"
    @State private var commandName: String = "claude-work"
    @State private var envVar: String = "CLAUDE_CONFIG_DIR"
    @State private var realBinaryPath: String = ""
    @State private var customEnvString: String = ""
    @State private var errorMessage: String?
    @State private var isCreating: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add CLI Profile")
                        .font(.headline)
                    Text("Creates a wrapper executable script in ~/.local/bin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Preset Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLI Tool Preset")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Picker("Preset", selection: $preset) {
                        ForEach(CLIPreset.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: preset) { newPreset in
                        applyPreset(newPreset)
                    }
                }

                // Command Name & Profile Name
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile Label")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("e.g. Work, Personal", text: $profileName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Terminal Command Alias")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("e.g. claude-work", text: $commandName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Environment variable
                VStack(alignment: .leading, spacing: 6) {
                    Text("Config Environment Variable")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    TextField("ENV_VAR_NAME", text: $envVar)
                        .textFieldStyle(.roundedBorder)
                }

                // Real binary path
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Target Executable Path")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Auto-detect") {
                            detectBinary()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    HStack {
                        TextField("/path/to/binary", text: $realBinaryPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") {
                            browseBinary()
                        }
                    }
                }

                // Data Directory Preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("Isolated Profile Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("~/Library/Application Support/Twinly/CLIProfiles/\(commandName.isEmpty ? "name" : commandName)")
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()

            Spacer()
            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create CLI Profile") {
                    createCLIProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(commandName.trimmingCharacters(in: .whitespaces).isEmpty || realBinaryPath.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
        .onAppear {
            applyPreset(preset)
        }
    }

    private func applyPreset(_ preset: CLIPreset) {
        envVar = preset.defaultEnvVar
        if preset != .custom {
            let prefix = preset.defaultCommandPrefix
            commandName = "\(prefix)-work"
            detectBinary()
        }
    }

    private func detectBinary() {
        if let found = CLIWrapperBuilder.shared.findRealBinary(for: preset.defaultBinaryName) {
            realBinaryPath = found
        }
    }

    private func browseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            realBinaryPath = url.path
        }
    }

    private func createCLIProfile() {
        isCreating = true
        errorMessage = nil

        var env = [String: String]()
        for line in customEnvString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let k = String(trimmed[..<eqIdx])
            let v = String(trimmed[trimmed.index(after: eqIdx)...])
            env[k] = v
        }

        do {
            let cliProfile = try CLIWrapperBuilder.shared.buildCLIWrapper(
                name: profileName,
                commandName: commandName,
                preset: preset,
                configEnvVar: envVar,
                realBinaryPath: realBinaryPath,
                customEnv: env
            )
            store.addCLIProfile(cliProfile)
            isCreating = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
