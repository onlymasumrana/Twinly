import SwiftUI
import AppKit
import TwinlyCore

struct CLIProfileSheet: View {
    enum Mode {
        case new(template: CLIProfile?)
        case edit(CLIProfile)
    }

    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var preset: CLIPreset = .claudeCode
    @State private var name = "Work"
    @State private var command = "claude-work"
    @State private var commandEdited = false
    @State private var binaryPath = ""
    @State private var configVar = "CLAUDE_CONFIG_DIR"
    @State private var environment = ""
    @State private var showAdvanced = false
    @State private var advancedHovered = false
    @State private var isFinding = false
    @State private var isSaving = false
    @State private var buildError: String?

    private var editing: CLIProfile? {
        if case .edit(let p) = mode { return p }
        return nil
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .edit(let p):
            _preset = State(initialValue: p.preset)
            _name = State(initialValue: p.name)
            _command = State(initialValue: p.commandName)
            _commandEdited = State(initialValue: true)
            _binaryPath = State(initialValue: p.realBinaryPath)
            _configVar = State(initialValue: p.configEnvVar)
            _environment = State(initialValue: InputParsing.formatEnvironment(p.customEnv))
            _showAdvanced = State(initialValue: p.preset == .custom)
        case .new(let template?):
            _preset = State(initialValue: template.preset)
            _name = State(initialValue: template.name)
            _command = State(initialValue: "\(template.commandName)-2")
            _commandEdited = State(initialValue: true)
            _binaryPath = State(initialValue: template.realBinaryPath)
            _configVar = State(initialValue: template.configEnvVar)
            _environment = State(initialValue: InputParsing.formatEnvironment(template.customEnv))
            _showAdvanced = State(initialValue: template.preset == .custom)
        case .new(nil):
            _showAdvanced = State(initialValue: false)
        }
    }

    private var title: String {
        if let e = editing { return "Edit “\(e.commandName)”" }
        return "New Command-Line Profile"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Form {
                Section("Tool") {
                    Picker("Tool", selection: $preset) {
                        ForEach(CLIPreset.allCases, id: \.self) { Text($0.shortName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(editing != nil)
                }

                Section("Profile") {
                    TextField("Name", text: $name, prompt: Text("Work"))
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Command", text: $command, prompt: Text("\(preset.defaultCommandPrefix)-work"))
                            .font(.system(.body, design: .monospaced))
                        if let commandError = commandError {
                            InlineError(text: commandError)
                        } else {
                            Text("You'll run it as `\(command.isEmpty ? "\(preset.defaultCommandPrefix)-work" : command)` in any terminal.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Runs") {
                    HStack {
                        Text(binaryPath.isEmpty ? "No program chosen" : binaryPath)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(binaryPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        if isFinding { ProgressView().controlSize(.small) }
                        Button("Find Automatically") { findBinary() }
                            .disabled(preset.defaultBinaryName.isEmpty || isFinding)
                        Button("Choose…", action: chooseBinary)
                    }
                    binaryStatus
                }

                Section {
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                            showAdvanced.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                                .frame(width: 12)
                            Text("Advanced")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(advancedHovered ? Color.primary.opacity(0.05) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hover in withAnimation(.easeOut(duration: 0.14)) { advancedHovered = hover } }

                    if showAdvanced {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Config variable", text: $configVar)
                                .font(.system(.body, design: .monospaced))
                            if let configVarError = configVarError { InlineError(text: configVarError) }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Environment")
                            TextEditor(text: $environment)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 64)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
                            if let envError = envError {
                                InlineError(text: envError)
                            } else {
                                Text("One per line, as KEY=value.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        LabeledContent("Config folder") {
                            Text(configFolderPath)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if let buildError = buildError {
                    Section { ErrorRow(text: buildError) }
                }
            }
            .formStyle(.grouped)

            Divider()
            SheetFooter(
                confirmTitle: editing == nil ? "Create Command" : "Save",
                canConfirm: canSave,
                isWorking: isSaving,
                cancel: { dismiss() },
                confirm: save
            )
        }
        .frame(width: 520)
        .frame(minHeight: 520)
        .onChange(of: preset) { newValue in
            guard editing == nil else { return }
            configVar = newValue.defaultEnvVar
            showAdvanced = newValue == .custom
            binaryPath = ""
            if !commandEdited { updateAutoCommand() }
            findBinary()
        }
        .onChange(of: name) { _ in
            if !commandEdited { updateAutoCommand() }
        }
        .onChange(of: command) { _ in
            // A change that doesn't match the auto value means the user typed it.
            if command != autoCommand { commandEdited = true }
        }
        .onAppear {
            if case .new(nil) = mode {
                configVar = preset.defaultEnvVar
                updateAutoCommand()
            }
            if binaryPath.isEmpty { findBinary() }
        }
    }

    // MARK: Binary status

    @ViewBuilder
    private var binaryStatus: some View {
        if let error = binaryError, !binaryPath.isEmpty {
            WarningRow(text: error)
        } else if !binaryPath.isEmpty {
            Label("Found \(URL(fileURLWithPath: binaryPath).lastPathComponent) at \(binaryPath)", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        } else if preset == .custom {
            Text("Choose the program to run.").font(.callout).foregroundStyle(.secondary)
        } else if !isFinding {
            WarningRow(text: "Couldn't find \(preset.defaultBinaryName). Install it or choose it manually.")
        }
    }

    // MARK: Validation

    private var autoCommand: String {
        let slug = WrapperBuilder.shared.sanitizeSlug(name)
        return slug.isEmpty ? "" : "\(preset.defaultCommandPrefix)-\(slug)"
    }

    private var trimmedCommand: String { command.trimmingCharacters(in: .whitespaces) }

    private var commandError: String? {
        let cmd = trimmedCommand
        if cmd.isEmpty { return "Enter a command name." }
        if !ShellEnvironment.isValidCommandName(cmd) { return "Use letters, numbers, dots, dashes or underscores." }
        if !preset.defaultBinaryName.isEmpty && cmd == preset.defaultBinaryName {
            return "This would replace the real `\(cmd)`. Pick another name like \(cmd)-work."
        }
        if store.cliProfiles.contains(where: { $0.id != editing?.id && $0.commandName == cmd }) {
            return "Another profile already uses \(cmd)."
        }
        let script = CLIWrapperBuilder.defaultBinDir.appendingPathComponent(cmd).path
        if FileManager.default.fileExists(atPath: script) && !ShellEnvironment.hasTwinlyMarker(path: script) {
            return "~/.local/bin/\(cmd) already exists and wasn't made by Twinly."
        }
        return nil
    }

    private var configVarError: String? {
        ShellEnvironment.isValidEnvName(configVar) ? nil : "Use letters, numbers and underscores, not starting with a number."
    }

    private var envError: String? {
        if case .failure(let error) = InputParsing.parseEnvironment(environment) { return error.localizedDescription }
        return nil
    }

    private var binaryError: String? {
        guard !binaryPath.isEmpty else { return nil }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: binaryPath, isDirectory: &isDir), !isDir.boolValue else { return "\(binaryPath) doesn't exist." }
        guard fm.isExecutableFile(atPath: binaryPath) else { return "\(binaryPath) isn't executable." }
        let script = CLIWrapperBuilder.defaultBinDir.appendingPathComponent(trimmedCommand).path
        if ShellEnvironment.hasTwinlyMarker(path: binaryPath)
            || URL(fileURLWithPath: binaryPath).resolvingSymlinksInPath().path == URL(fileURLWithPath: script).resolvingSymlinksInPath().path {
            return "The command can't run itself. Choose the real program."
        }
        return nil
    }

    private var configFolderPath: String {
        if let e = editing { return e.profileDirectory }
        let leaf = trimmedCommand.isEmpty ? "<command>" : trimmedCommand
        return CLIWrapperBuilder.defaultCLIProfilesDir.appendingPathComponent(leaf).path
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && commandError == nil && configVarError == nil && envError == nil
            && !binaryPath.isEmpty && binaryError == nil
    }

    // MARK: Actions

    private func updateAutoCommand() {
        command = autoCommand
    }

    private func findBinary() {
        let target = preset.defaultBinaryName
        guard !target.isEmpty else { return }
        isFinding = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                CLIWrapperBuilder.shared.findRealBinary(for: target)
            }.value
            await MainActor.run {
                isFinding = false
                if preset.defaultBinaryName == target, let found = found { binaryPath = found }
            }
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.title = "Choose the program to run"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { binaryPath = url.path }
    }

    private func save() {
        guard canSave, case .success(let env) = InputParsing.parseEnvironment(environment) else { return }
        isSaving = true
        buildError = nil
        let args = (name: name.trimmingCharacters(in: .whitespaces), command: trimmedCommand,
                    preset: preset, configVar: configVar, binary: binaryPath, env: env, existing: editing)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try CLIWrapperBuilder.shared.buildCLIWrapper(
                        name: args.name, commandName: args.command, preset: args.preset,
                        configEnvVar: args.configVar, realBinaryPath: args.binary,
                        customEnv: args.env, existing: args.existing)
                }
            }.value
            await MainActor.run {
                isSaving = false
                switch result {
                case .success(let profile):
                    if editing == nil {
                        store.addCLIProfile(profile)
                    } else {
                        store.updateCLIProfile(profile)
                    }
                    ui.cliSelection = [profile.id]
                    dismiss()
                case .failure(let error):
                    buildError = error.localizedDescription
                }
            }
        }
    }
}
