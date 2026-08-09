//  ProgressSection.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

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
