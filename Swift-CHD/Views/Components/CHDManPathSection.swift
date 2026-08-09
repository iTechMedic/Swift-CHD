//  CHDManPathSection.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import SwiftUI

struct CHDManPathSection: View {
    @Binding var chdmanPath: String
    let chdmanVerified: Bool
    let chdmanNotFoundHelp: String?
    let onVerify: () async -> Void

    /// The text field edits this, not the view model directly.
    ///
    /// A TextField bound straight to an @Published property writes back through the binding as
    /// its writeback buffer deallocates - which, when this view is torn down mid-update by a
    /// mode switch, publishes from inside a view update. Local state absorbs that write instead.
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("chdman:")
                TextField("Path to chdman (or leave as 'chdman')", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { draft = chdmanPath }
                    // onChange runs after the update, so publishing from here is safe.
                    .onChange(of: draft) { _, new in
                        if new != chdmanPath { chdmanPath = new }
                    }
                    .onChange(of: chdmanPath) { _, new in
                        if new != draft { draft = new }
                    }
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
