import SwiftUI
import TwinlyCore

struct StrategyChip: View {
    let strategy: AppStrategy

    var body: some View {
        Text(strategy.displayName)
            .font(.caption)
            .foregroundStyle(strategy == .sandboxedUnsupported ? Color.red : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(strategy == .sandboxedUnsupported ? Color.red.opacity(0.12) : Color.secondary.opacity(0.12))
            )
            .help(strategy.isolationSummary)
    }
}
