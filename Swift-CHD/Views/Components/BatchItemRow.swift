import SwiftUI

struct BatchItemRow: View {
    let item: BatchConversionItem
    let isRunning: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.status.icon)
                .foregroundStyle(Color(item.status.color))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.inputURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                Text(item.outputURL.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let error = item.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.status == .processing {
                ProgressView(value: item.progress)
                    .frame(width: 80)
                Text(String(format: "%.0f%%", item.progress * 100))
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 35)
            } else {
                Text(item.status.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }
}

// MARK: - Color Extension for BatchItemStatus

private extension Color {
    init(_ colorName: String) {
        switch colorName {
        case "gray": self = .gray
        case "blue": self = .blue
        case "green": self = .green
        case "red": self = .red
        case "orange": self = .orange
        default: self = .primary
        }
    }
}
