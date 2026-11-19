import SwiftUI
import TwinlyCore

struct NewAppProfileSheet: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    let prefill: URL?

    @State private var inspectingURL: URL?
    @State private var analysis: AppAnalysis?
    @State private var inspectError: String?
    @State private var buildError: String?
    @State private var isCreating = false
    @State private var isDropTargeted = false
    @State private var appSearch = ""
    @State private var allApps: [InstalledApp] = []

    @State private var name = "Work"
    @State private var badgeText = "W"
    @State private var badgeHex = "#3B82F6"
    @State private var arguments = ""
    @State private var environment = ""
    @State private var separateDockIcon = true

    var body: some View {
        VStack(spacing: 0) {
            Text("New App Profile")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if let analysis = analysis {
                stepTwo(analysis)
            } else {
                stepOne
            }

            Divider()
            SheetFooter(
                confirmTitle: "Create Profile",
                canConfirm: canCreate,
                isWorking: isCreating,
                cancel: { dismiss() },
                confirm: create
            )
        }
        .frame(width: 560)
        .frame(minHeight: 460)
        .onAppear {
            Task {
                let apps = await Task.detached { InstalledApp.loadAll() }.value
                allApps = apps
            }
            if let prefill = prefill, analysis == nil, inspectingURL == nil { inspect(prefill) }
        }
    }

    // MARK: Step 1

    private var stepOne: some View {
        VStack(spacing: 14) {
            if let url = inspectingURL {
                Spacer(minLength: 0)
                ProgressView("Checking \(url.deletingPathExtension().lastPathComponent)…")
                Spacer(minLength: 0)
            } else {
                searchBar
                appList

                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.app")
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                    Text("Drop any .app here, or").font(.callout).foregroundStyle(.secondary)
                    Button("Choose from Finder…") {
                        if let url = AppPicker.chooseApp() { inspect(url) }
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                )

                if let inspectError = inspectError {
                    ErrorRow(text: inspectError)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 320)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            AppPicker.loadApp(from: providers) { inspect($0) }
        }
    }

    private var filteredApps: [InstalledApp] {
        let q = appSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return allApps }
        return allApps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search installed apps…", text: $appSearch)
                .textFieldStyle(.plain)
                .onSubmit { if let first = filteredApps.first { inspect(first.url) } }
            if !appSearch.isEmpty {
                Button { appSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
        )
    }

    private var appList: some View {
        ScrollView {
            if filteredApps.isEmpty {
                Text(allApps.isEmpty ? "Loading apps…" : "No installed apps match \"\(appSearch)\"")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps) { app in
                        AppPickerRow(app: app) { inspect(app.url) }
                    }
                }
                .padding(4)
            }
        }
        .frame(height: 210)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Step 2

    private func stepTwo(_ analysis: AppAnalysis) -> some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    BadgedIcon(appPath: analysis.appURL.path, hex: badgeHex, text: badgeText, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(analysis.appName).font(.title3.weight(.semibold))
                        HStack(spacing: 6) {
                            Text(analysis.bundleIdentifier)
                                .font(.callout).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            StrategyChip(strategy: analysis.strategy)
                        }
                        Text(analysis.strategy.isolationSummary)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change App…") { reset() }
                        .buttonStyle(.link)
                }
            }

            if analysis.strategy == .sandboxedUnsupported {
                Section {
                    GroupBox {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Twinly can't copy this app").font(.headline)
                                Text("\(analysis.appName) is a sandboxed (App Store) app. macOS locks its data to one copy, so Twinly can't make a separate profile without changing the app.")
                                    .font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(4)
                    }
                    .backgroundStyle(Color.orange.opacity(0.12))
                }
            } else {
                ProfileFormFields(
                    name: $name, badgeHex: $badgeHex, badgeText: $badgeText,
                    arguments: $arguments, environment: $environment, separateDockIcon: $separateDockIcon,
                    nameError: nameError, envError: envError
                )
            }

            if let buildError = buildError {
                Section { ErrorRow(text: buildError) }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Validation

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var nameError: String? {
        guard let analysis = analysis else { return nil }
        if trimmedName.isEmpty { return "Enter a name." }
        let clash = store.profiles.contains {
            $0.originalAppPath == analysis.appURL.path && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
        return clash ? "You already have a “\(trimmedName)” profile for \(analysis.appName)." : nil
    }

    private var envError: String? {
        if case .failure(let error) = InputParsing.parseEnvironment(environment) { return error.localizedDescription }
        return nil
    }

    private var canCreate: Bool {
        guard let analysis = analysis, analysis.strategy != .sandboxedUnsupported else { return false }
        return nameError == nil && envError == nil
    }

    // MARK: Actions

    private func reset() {
        analysis = nil
        inspectingURL = nil
        inspectError = nil
        buildError = nil
    }

    private func inspect(_ url: URL) {
        inspectingURL = url
        inspectError = nil
        buildError = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try AppInspector.shared.inspect(appURL: url) }
            }.value
            await MainActor.run {
                inspectingURL = nil
                switch result {
                case .success(let found):
                    analysis = found
                    applyDefaults(for: found)
                case .failure(let error):
                    inspectError = error.localizedDescription
                }
            }
        }
    }

    private func applyDefaults(for analysis: AppAnalysis) {
        let existing = store.profiles.filter { $0.originalAppPath == analysis.appURL.path }
        let taken = Set(existing.map { $0.name.lowercased() })
        if existing.isEmpty {
            name = "Work"
            badgeText = "W"
        } else {
            var n = existing.count + 1
            while taken.contains("profile \(n)") { n += 1 }
            name = "Profile \(n)"
            badgeText = String(n)
        }
        let colors = BadgeColorPicker.presets
        badgeHex = colors[existing.count % colors.count].hex
    }

    private func create() {
        guard let analysis = analysis, canCreate,
              case .success(let env) = InputParsing.parseEnvironment(environment) else { return }
        isCreating = true
        buildError = nil
        let args = InputParsing.tokenizeArguments(arguments)
        let profileName = trimmedName
        let hex = badgeHex
        let text = badgeText
        let separate = separateDockIcon
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try WrapperBuilder.shared.buildWrapper(
                        analysis: analysis, profileName: profileName,
                        badgeColorHex: hex, badgeText: text,
                        customArgs: args, customEnv: env, separateDockIcon: separate)
                }
            }.value
            await MainActor.run {
                isCreating = false
                switch result {
                case .success(let profile):
                    store.addProfile(profile)
                    ui.selection = [profile.id]
                    dismiss()
                case .failure(let error):
                    buildError = error.localizedDescription
                }
            }
        }
    }
}
