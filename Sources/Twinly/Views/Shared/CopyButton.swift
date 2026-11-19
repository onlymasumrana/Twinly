import SwiftUI
import AppKit

struct CopyButton: View {
    let text: String
    var help: String = "Copy"
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .id(copied)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.65), value: copied)
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
