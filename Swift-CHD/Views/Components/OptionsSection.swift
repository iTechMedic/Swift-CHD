//  OptionsSection.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import SwiftUI

struct OptionsSection: View {
    @Binding var options: [SwiftCHDOption]
    @Binding var advancedMode: Bool
    let conversionType: ConversionType

    var body: some View {
        GroupBox(label: Label("Options", systemImage: "slider.horizontal.3")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(advancedMode ? "Advanced Mode" : "Simple Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Advanced", isOn: $advancedMode)
                        .toggleStyle(.switch)
                }

                if options.isEmpty {
                    Text("No options enabled. Toggle 'Advanced' to see all available options.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                }

                Divider()

                ForEach($options) { $opt in
                    OptionRow(option: $opt, conversionType: conversionType)
                }
            }
            .padding(8)
        }
    }
}

struct OptionRow: View {
    @Binding var option: SwiftCHDOption
    let conversionType: ConversionType

    /// Edited by the text field instead of `option` itself - see `CHDManPathSection.draft` for
    /// why a TextField must not write straight into an @Published value.
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                // Enable/Disable toggle
                Toggle(isOn: $option.isEnabled) {
                    Text(option.key)
                        .monospaced()
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 40, alignment: .leading)
                }
                .toggleStyle(.switch)
                .help("Enable/disable \(option.key)")

                // Value input based on type
                switch option.type {
                case .flag:
                    Text("(flag)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)

                case .text:
                    TextField("value", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .disabled(!option.isEnabled)
                        .onAppear { draft = option.value ?? "" }
                        .onChange(of: draft) { _, new in
                            let value = new.isEmpty ? nil : new
                            if value != option.value { option.value = value }
                        }
                        .onChange(of: option.value) { _, new in
                            if (new ?? "") != draft { draft = new ?? "" }
                        }

                case .dropdown(let choices):
                    Picker("", selection: $option.value) {
                        ForEach(choices, id: \.self) { choice in
                            Text(choice).tag(choice as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .disabled(!option.isEnabled)
                }

                // Help text
                Text(option.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()
            }

            // Show codec description if this is the compression codec option
            if option.key == "-c", option.isEnabled, let codec = option.value,
               let description = ConversionType.codecDescriptions[codec] {
                Text("\u{2139}\u{FE0F} \(description)")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .padding(.leading, 60)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
