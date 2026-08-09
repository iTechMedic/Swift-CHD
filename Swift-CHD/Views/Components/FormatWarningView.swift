import SwiftUI

/// Explains why the selected conversion cannot run, shown in place of letting the user start a
/// job chdman would only stall or fail on.
struct FormatWarningView: View {
    let message: String

    /// Upstream record that CDI support was declined, so the claim in the message is checkable.
    private static let mameIssueURL = URL(string: "https://github.com/mamedev/mame/issues/11457")!

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    // fixedSize takes the text's height at whatever width it is offered, and
                    // SwiftUI proposes width 0 when measuring a view's *minimum* size. Without
                    // a minWidth the text then wraps to one character per line, reporting a
                    // minimum height of several thousand points - which the window adopts.
                    // minWidth is what keeps that measurement sane; maxWidth just keeps the
                    // line length readable.
                    .frame(minWidth: 380, idealWidth: 520, maxWidth: 560, alignment: .leading)

                Link("Why chdman can't do this", destination: Self.mameIssueURL)
                    .font(.caption)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}
