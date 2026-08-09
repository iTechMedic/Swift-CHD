//  FormatWarningView.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import SwiftUI

/// Explains why the selected conversion cannot run. The message is always about the chosen file
/// and carries its own explanation, so nothing further is linked.
struct FormatWarningView: View {
    let message: String

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
                    // SwiftUI proposes width 0 when measuring minimum size, so without minWidth
                    // the text wraps one character per line and the window adopts that height.
                    .frame(minWidth: 380, idealWidth: 520, maxWidth: 560, alignment: .leading)
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
