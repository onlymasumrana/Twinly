import SwiftUI

/// Secondary status text for a row: running, missing, or when it was last opened.
struct StatusLine: View {
    enum Kind {
        case running
        case missing(help: String, label: String)
        case lastOpened(Date?)
    }
    let kind: Kind

    var body: some View {
        switch kind {
        case .running:
            HStack(spacing: 4) {
                RunningDot()
                Text("Running")
            }
        case .missing(let help, let label):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(label)
            }
            .help(help)
        case .lastOpened(let date):
            if let date = date {
                Text("Opened \(date.formatted(.relative(presentation: .named)))")
            } else {
                Text("Not opened yet")
            }
        }
    }
}

/// Green dot with a softly pulsing halo for active instances.
private struct RunningDot: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.28))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.0 : 0.65)
                .opacity(pulse ? 0.5 : 1.0)
            Circle().fill(Color.green).frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
