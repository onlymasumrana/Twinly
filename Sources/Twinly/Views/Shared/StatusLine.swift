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
                Circle().fill(Color.green).frame(width: 8, height: 8)
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
