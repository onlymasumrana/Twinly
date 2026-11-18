import SwiftUI
import TwinlyCore

struct TwinlyCommands: Commands {
    @ObservedObject var ui: UIState
    let openMain: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New App Profile…") {
                openMain()
                ui.section = .apps
                ui.sheet = .newApp(prefill: nil)
            }
            .keyboardShortcut("n")

            Button("New Command-Line Profile…") {
                openMain()
                ui.section = .commandLine
                ui.sheet = .newCLI(template: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Repair All Shortcuts…") { ui.repairAll() }
                .disabled(ui.isRepairing)
        }

        CommandMenu("Profile") {
            Button("Open") { ui.openSelected() }
                .keyboardShortcut("o")
                .disabled(!ui.hasSelection)
            Button("Edit…") { ui.editSelected() }
                .keyboardShortcut("i")
                .disabled(!ui.hasSelection)
            Button("Duplicate") { ui.duplicateSelected() }
                .keyboardShortcut("d")
                .disabled(!ui.hasSelection)
            Divider()
            Button("Show in Finder") { ui.showSelectedInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!ui.hasSelection)
            Divider()
            Button("Delete…") { ui.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!ui.hasSelection)
        }

        CommandGroup(after: .sidebar) {
            Button("Apps") { ui.section = .apps }
                .keyboardShortcut("1")
            Button("Command Line") { ui.section = .commandLine }
                .keyboardShortcut("2")
            Button("How It Works") { ui.section = .howItWorks }
                .keyboardShortcut("3")
        }
    }
}
