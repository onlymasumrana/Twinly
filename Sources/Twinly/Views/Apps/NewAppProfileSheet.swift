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
    @State private var dropZoneHovered = false
    @State private var isSearchHovered = false
    @State private var appSearch = ""
    @State private var isSearchOpen = false
    @State private var canOpenOnFocus = false
    @FocusState private var searchFocused: Bool
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

            ZStack {
                if let analysis = analysis {
                    stepTwo(analysis)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    stepOne
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: analysis == nil)

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
            isSearchOpen = false
            DispatchQueue.main.async { searchFocused = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { canOpenOnFocus = true }
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
                ZStack(alignment: .top) {
                    dropZone
                    if isSearchOpen {
                        appList
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                }
                .frame(maxHeight: .infinity)

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

    private func setSearchOpen(_ open: Bool) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) { isSearchOpen = open }
    }

    private func closeSearch() {
        appSearch = ""
        setSearchOpen(false)
        searchFocused = false
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 36))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .offset(y: (isDropTargeted || dropZoneHovered) ? -2 : 0)
            Text("Drop an app here").font(.headline)
            Text("or").font(.callout).foregroundStyle(.secondary)
            Button("Choose App…") {
                if let url = AppPicker.chooseApp() { inspect(url) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
        .scaleEffect(isDropTargeted ? 1.015 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isDropTargeted)
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: dropZoneHovered)
        .contentShape(Rectangle())
        .onHover { dropZoneHovered = $0 }
        .onTapGesture { closeSearch() }
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
                .focused($searchFocused)
                .onChange(of: searchFocused) { focused in
                    if focused && canOpenOnFocus { setSearchOpen(true) }
                }
                .onChange(of: appSearch) { new in
                    if !new.isEmpty { setSearchOpen(true) }
                }
                .onSubmit { if let first = filteredApps.first { closeSearch(); inspect(first.url) } }
            if isSearchOpen || !appSearch.isEmpty {
                Button { closeSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .overlay {
            if !isSearchOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { setSearchOpen(true); searchFocused = true }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(searchBorderColor, lineWidth: 1)
        )
        .shadow(color: (isSearchOpen || searchFocused) ? Color.accentColor.opacity(0.18) : .clear, radius: 4)
        .animation(.easeOut(duration: 0.15), value: isSearchHovered)
        .animation(.easeOut(duration: 0.15), value: searchFocused)
        .onHover { isSearchHovered = $0 }
    }

    private var searchBorderColor: Color {
        if isSearchOpen || searchFocused { return Color.accentColor.opacity(0.8) }
        return Color.secondary.opacity(isSearchHovered ? 0.55 : 0.35)
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
                        AppPickerRow(app: app) { closeSearch(); inspect(app.url) }
                    }
                }
                .padding(4)
            }
        }
        .frame(height: 210)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            analysis = nil
            inspectingURL = nil
            inspectError = nil
            buildError = nil
        }
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
                    applyDefaults(for: found)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { analysis = found }
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
