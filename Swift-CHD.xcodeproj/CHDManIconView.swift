import Foundation
import SwiftUI

struct CHDManIconView: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(colors: [
                Color(red: 0.04, green: 0.16, blue: 0.42), // #0A2A6B
                Color(red: 0.42, green: 0.07, blue: 0.80)  // #6A11CB
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                // Soft inner glow
                RadialGradient(colors: [Color.white.opacity(0.08), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 600)
            }
            .clipShape(RoundedRectangle(cornerRadius: 220, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 20)

            // Symbol
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 380, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 6)
        }
        .frame(width: 1024, height: 1024)
        .background(Color.clear)
        .accessibilityHidden(true)
    }
}

#Preview {
    CHDManIconView()
        .previewLayout(.sizeThatFits)
}
