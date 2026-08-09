//  ConsoleOutputView.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import SwiftUI

struct ConsoleOutputView: View {
    let consoleOutput: String

    var body: some View {
        GroupBox(label: Label("Console Output", systemImage: "terminal")) {
            ScrollView {
                ScrollViewReader { proxy in
                    Text(consoleOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("consoleBottom")
                        .onChange(of: consoleOutput) { _, _ in
                            proxy.scrollTo("consoleBottom", anchor: .bottom)
                        }
                }
            }
            .frame(height: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
        }
    }
}
