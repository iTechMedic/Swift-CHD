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
                    TextField("value", text: Binding(
                        get: { option.value ?? "" },
                        set: { option.value = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .disabled(!option.isEnabled)

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
