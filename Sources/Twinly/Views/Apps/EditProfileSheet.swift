import SwiftUI
import TwinlyCore

struct EditProfileSheet: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    let profile: Profile

    @State private var name: String
    @State private var badgeHex: String
    @State private var badgeText: String
    @State private var arguments: String
    @State private var environment: String
    @State private var isSaving = false
    @State private var saveError: String?

    init(profile: Profile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _badgeHex = State(initialValue: profile.badgeColorHex)
        _badgeText = State(initialValue: profile.badgeText)
        _arguments = State(initialValue: InputParsing.formatArguments(profile.customArgs))
        _environment = State(initialValue: InputParsing.formatEnvironment(profile.customEnv))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var missing: Bool { ProfileStatus.isOriginalMissing(profile) }

    private var nameError: String? {
        if trimmedName.isEmpty { return "Enter a name." }
        let clash = store.profiles.contains {
            $0.id != profile.id && $0.originalAppPath == profile.originalAppPath
                && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
        return clash ? "You already have a “\(trimmedName)” profile for \(profile.appName)." : nil
    }

    private var envError: String? {
        if case .failure(let error) = InputParsing.parseEnvironment(environment) { return error.localizedDescription }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit “\(profile.appName) (\(profile.name))”")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Form {
                Section {
                    HStack(spacing: 12) {
                        BadgedIcon(appPath: profile.originalAppPath, hex: badgeHex, text: badgeText, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.appName).font(.title3.weight(.semibold))
                            HStack(spacing: 6) {
                                Text(profile.originalBundleId)
                                    .font(.callout).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                StrategyChip(strategy: profile.strategy)
                            }
                        }
                        Spacer()
                    }
                    if missing {
                        WarningRow(text: "\(profile.appName) can't be found at \(profile.originalAppPath). You can still change the name and badge, but the shortcut won't open until the app is back.")
                    }
                }

                ProfileFormFields(
                    name: $name, badgeHex: $badgeHex, badgeText: $badgeText,
                    arguments: $arguments, environment: $environment,
                    nameError: nameError, envError: envError
                )

                if let saveError = saveError {
                    Section { ErrorRow(text: saveError) }
                }
            }
            .formStyle(.grouped)

            Divider()
            SheetFooter(
                confirmTitle: "Save",
                canConfirm: nameError == nil && envError == nil,
                isWorking: isSaving,
                cancel: { dismiss() },
                confirm: save
            )
        }
        .frame(width: 560)
        .frame(minHeight: 460)
    }

    private func save() {
        guard case .success(let env) = InputParsing.parseEnvironment(environment) else { return }
        var updated = profile
        updated.name = trimmedName
        updated.badgeColorHex = badgeHex
        updated.badgeText = badgeText
        updated.customArgs = InputParsing.tokenizeArguments(arguments)
        updated.customEnv = env

        if missing {
            store.updateProfile(updated)
            dismiss()
            ui.alert = AlertItem(
                title: "Saved Without Rebuilding",
                message: "\(profile.appName) can't be found, so the shortcut wasn't rebuilt. Reinstall it, then choose Repair All Shortcuts in Settings."
            )
            return
        }

        isSaving = true
        saveError = nil
        let store = self.store
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try store.updateAndRebuild(updated) }
            }.value
            await MainActor.run {
                isSaving = false
                switch result {
                case .success: dismiss()
                case .failure(let error): saveError = error.localizedDescription
                }
            }
        }
    }
}
