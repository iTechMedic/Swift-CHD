import SwiftUI
import UniformTypeIdentifiers

struct SingleModeView: View {
    @ObservedObject var vm: ConversionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("Conversion", systemImage: "arrow.triangle.2.circlepath")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.conversionType.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Label("Paths", systemImage: "folder")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Input:")
                        Text(vm.inputURL?.path ?? "Choose input...")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Browse...") { chooseInput() }
                    }
                    HStack {
                        Text("Output:")
                        Text(vm.outputURL?.path ?? "Choose output...")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Browse...") { chooseOutput() }
                    }
                    CHDManPathSection(
                        chdmanPath: $vm.chdmanPath,
                        chdmanVerified: vm.chdmanVerified,
                        chdmanNotFoundHelp: vm.chdmanNotFoundHelp,
                        onVerify: { await vm.verifyCHDMan() }
                    )
                }
            }

            OptionsSection(
                options: $vm.options,
                advancedMode: $vm.advancedMode,
                conversionType: vm.conversionType
            )

            if vm.isRunning {
                ProgressSection(progress: vm.progress, statusLine: vm.statusLine)
            }

            HStack {
                Button(role: .none) {
                    Task { await vm.start() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isRunning || vm.inputURL == nil || vm.outputURL == nil || !vm.chdmanVerified)

                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(3)
                }
                Spacer()
            }

            if !vm.consoleOutput.isEmpty {
                ConsoleOutputView(consoleOutput: vm.consoleOutput)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - File Pickers

    private func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        // Use the extension from ConversionType
        panel.allowedContentTypes = [.init(filenameExtension: vm.conversionType.inputExtension)!]

        if panel.runModal() == .OK {
            vm.inputURL = panel.url
        }
    }

    private func chooseOutput() {
        let panel = NSSavePanel()

        // Use the extension from ConversionType
        let ext = vm.conversionType.outputExtension
        panel.allowedContentTypes = [.init(filenameExtension: ext)!]
        panel.nameFieldStringValue = suggestedOutputName(ext: ext)

        if panel.runModal() == .OK {
            vm.outputURL = panel.url
        }
    }

    private func suggestedOutputName(ext: String) -> String {
        if let input = vm.inputURL {
            return input.deletingPathExtension().lastPathComponent + "." + ext
        }
        return "output." + ext
    }
}
