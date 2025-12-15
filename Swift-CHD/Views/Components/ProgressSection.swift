import SwiftUI

struct ProgressSection: View {
    let progress: Double
    let statusLine: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .frame(width: 240)
            Text(String(format: "%.0f%%", progress * 100))
                .monospacedDigit()
            Text(statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
