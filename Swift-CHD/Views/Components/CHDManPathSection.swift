import SwiftUI

struct CHDManPathSection: View {
    @Binding var chdmanPath: String
    let chdmanVerified: Bool
    let chdmanNotFoundHelp: String?
    let onVerify: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("chdman:")
                TextField("Path to chdman (or leave as 'chdman')", text: $chdmanPath)
                    .textFieldStyle(.roundedBorder)
                Button("Verify") {
                    Task { await onVerify() }
                }
                .buttonStyle(.borderedProminent)
                if chdmanVerified {
                    Image(systemName: chdmanNotFoundHelp != nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(chdmanNotFoundHelp != nil ? .orange : .green)
                        .help(chdmanNotFoundHelp != nil ? "Path looks correct but couldn't verify" : "chdman found and verified")
                }
            }
            if let help = chdmanNotFoundHelp {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(chdmanVerified ? .orange : .red)
                    .padding(.top, 4)
                    .textSelection(.enabled)
            }
        }
    }
}
