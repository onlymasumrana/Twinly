import SwiftUI
import TwinlyCore

/// Shared form sections for the New and Edit app profile sheets.
struct ProfileFormFields: View {
    @Binding var name: String
    @Binding var badgeHex: String
    @Binding var badgeText: String
    @Binding var arguments: String
    @Binding var environment: String
    @Binding var separateDockIcon: Bool
    let nameError: String?
    let envError: String?
    @State private var showAdvanced = false
    @State private var advancedHovered = false

    var body: some View {
        Section("Profile") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $name, prompt: Text("Work"))
                if let nameError = nameError { InlineError(text: nameError) }
            }
            LabeledContent("Badge color") { BadgeColorPicker(hex: $badgeHex) }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Badge text", text: $badgeText)
                    .onChange(of: badgeText) { value in
                        if value.count > 3 { badgeText = String(value.prefix(3)) }
                    }
                Text("Up to 3 characters or an emoji.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        Section {
            Toggle("Separate Dock icon while running (APFS zero-space clone)", isOn: $separateDockIcon)
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
                    TextField("Launch arguments", text: $arguments, prompt: Text("--incognito \"--x=a b\""))
                        .font(.system(.body, design: .monospaced))
                    Text("Separate with spaces. Use quotes for values with spaces.")
                        .font(.caption).foregroundStyle(.secondary)
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
            }
        }
    }
}

struct SheetFooter: View {
    let confirmTitle: String
    let canConfirm: Bool
    let isWorking: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button(action: confirm) {
                HStack(spacing: 6) {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(confirmTitle)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canConfirm || isWorking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
