import SwiftUI
import AppKit
import TwinlyCore

struct ProfilesListView: View {
    @ObservedObject var store: ProfileStore
    @Binding var showAddSheet: Bool

    @State private var searchText: String = ""
    @State private var profileToDelete: Profile?
    @State private var showDeleteConfirmation = false
    @State private var profileToEdit: Profile?

    var filteredProfiles: [Profile] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return store.profiles
        }
        return store.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.appName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search / Stats bar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search profiles…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: 280)

                Spacer()

                Text("\(store.profiles.count) Profile\(store.profiles.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { showAddSheet = true }) {
                    Label("Add Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if store.profiles.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProfiles) { profile in
                            profileCard(profile)
                        }
                    }
                    .padding()
                }
            }
        }
        .confirmationDialog(
            "Delete Profile",
            isPresented: $showDeleteConfirmation,
            presenting: profileToDelete
        ) { profile in
            Button("Delete Shortcut & All Profile Data", role: .destructive) {
                try? store.deleteProfile(id: profile.id, deleteData: true)
            }
            Button("Delete Shortcut Only (Keep Data)") {
                try? store.deleteProfile(id: profile.id, deleteData: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("Are you sure you want to delete '\(profile.appName) (\(profile.name))'?\nYou can keep the isolated data folder or permanently delete it.")
        }
        .sheet(item: $profileToEdit) { profile in
            EditProfileSheet(store: store, profile: profile)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No App Profiles Yet")
                .font(.title2)
                .fontWeight(.medium)
            Text("Create separate instances of Claude, Slack, Discord, Chrome, or VS Code with independent logins and data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button("Add First Profile") {
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func profileCard(_ profile: Profile) -> some View {
        HStack(spacing: 14) {
            // Icon
            BadgedIconPreviewView(
                baseImage: NSWorkspace.shared.icon(forFile: profile.originalAppPath),
                badgeColorHex: profile.badgeColorHex,
                badgeText: profile.badgeText,
                size: 52
            )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .font(.headline)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(profile.appName)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    StrategyBadgeView(strategy: profile.strategy)

                    if let last = profile.lastLaunchedAt {
                        Text("Launched \(relativeTime(last))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never launched")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                Button(action: { store.launchProfile(profile) }) {
                    Label("Launch", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    Button(action: { store.revealInFinder(path: profile.wrapperAppPath) }) {
                        Label("Reveal Shortcut in Finder", systemImage: "folder")
                    }

                    Button(action: { store.openFolder(path: profile.profileDirectory) }) {
                        Label("Open Data Folder", systemImage: "internaldrive")
                    }

                    Divider()

                    Button(action: { profileToEdit = profile }) {
                        Label("Edit Profile…", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        profileToDelete = profile
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Profile…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
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

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct EditProfileSheet: View {
    @ObservedObject var store: ProfileStore
    let profile: Profile
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var badgeText: String = ""
    @State private var badgeColorHex: String = "#3B82F6"
    @State private var isSaving = false

    let presetColors = [
        "#3B82F6", "#8B5CF6", "#EC4899", "#EF4444",
        "#F97316", "#F59E0B", "#10B981", "#06B6D4", "#6366F1", "#64748B"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Profile: \(profile.appName)")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    BadgedIconPreviewView(
                        baseImage: NSWorkspace.shared.icon(forFile: profile.originalAppPath),
                        badgeColorHex: badgeColorHex,
                        badgeText: badgeText,
                        size: 64
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Badge Color & Text")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(presetColors, id: \.self) { colorHex in
                            Circle()
                                .fill(Color(nsColor: NSColor(hex: colorHex) ?? .blue))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: badgeColorHex == colorHex ? 2.5 : 0)
                                )
                                .onTapGesture { badgeColorHex = colorHex }
                        }
                    }

                    HStack {
                        Text("Badge Character:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Text", text: $badgeText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
            }
            .padding()

            Spacer()
            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
            .padding()
        }
        .frame(width: 440, height: 360)
        .onAppear {
            name = profile.name
            badgeText = profile.badgeText
            badgeColorHex = profile.badgeColorHex
        }
    }

    private func saveChanges() {
        isSaving = true
        var updated = profile
        updated.name = name
        updated.badgeText = badgeText
        updated.badgeColorHex = badgeColorHex

        // Rebuild wrapper with new badge/name
        DispatchQueue.global(qos: .userInitiated).async {
            let origURL = URL(fileURLWithPath: profile.originalAppPath)
            if let analysis = try? AppInspector.shared.inspect(appURL: origURL) {
                _ = try? WrapperBuilder.shared.buildWrapper(
                    analysis: analysis,
                    profileName: name,
                    badgeColorHex: badgeColorHex,
                    badgeText: badgeText,
                    customArgs: profile.customArgs,
                    customEnv: profile.customEnv
                )
            }
            DispatchQueue.main.async {
                store.updateProfile(updated)
                isSaving = false
                dismiss()
            }
        }
    }
}
