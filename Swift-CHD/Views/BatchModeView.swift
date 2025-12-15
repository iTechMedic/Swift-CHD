import SwiftUI
import UniformTypeIdentifiers

struct BatchModeView: View {
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

            GroupBox(label: Label("Batch Files", systemImage: "doc.on.doc")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Add Files...") { chooseBatchInput() }
                        Button("Clear All") { vm.clearBatchItems() }
                            .disabled(vm.batchItems.isEmpty || vm.isRunning)
                        Spacer()
                        Text("\(vm.batchItems.count) file(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Output Directory:")
                        Text(vm.batchOutputDirectory?.path ?? "Same as input files")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose...") { chooseBatchOutputDirectory() }
                        if vm.batchOutputDirectory != nil {
                            Button("Reset") { vm.updateBatchOutputDirectory(nil) }
                        }
                    }

                    Divider()

                    // Batch items list
                    if vm.batchItems.isEmpty {
                        Text("No files added. Click 'Add Files...' to begin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(vm.batchItems) { item in
                                    BatchItemRow(
                                        item: item,
                                        isRunning: vm.isRunning,
                                        onRemove: { vm.removeBatchItem(item) }
                                    )
                                }
                            }
                        }
                        .frame(height: 200)
                    }
                }
            }

            GroupBox(label: Label("Batch Options", systemImage: "gearshape.2")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Skip existing files", isOn: $vm.batchConfig.skipExisting)
                    Toggle("Stop on first error", isOn: $vm.batchConfig.stopOnError)

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
                    Label("Run Batch", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isRunning || vm.batchItems.isEmpty || !vm.chdmanVerified)

                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(3)
                }
                Spacer()
            }

            // Batch Summary
            if let summary = vm.batchSummary {
                batchSummaryView(summary)
            }

            if !vm.consoleOutput.isEmpty {
                ConsoleOutputView(consoleOutput: vm.consoleOutput)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Batch Summary

    private func batchSummaryView(_ summary: BatchSummary) -> some View {
        GroupBox(label: Label("Batch Summary", systemImage: "chart.bar")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Total:")
                    Spacer()
                    Text("\(summary.total)")
                }
                HStack {
                    Text("Succeeded:")
                    Spacer()
                    Text("\(summary.succeeded)")
                        .foregroundStyle(.green)
                }
                HStack {
                    Text("Failed:")
                    Spacer()
                    Text("\(summary.failed)")
                        .foregroundStyle(.red)
                }
                HStack {
                    Text("Skipped:")
                    Spacer()
                    Text("\(summary.skipped)")
                        .foregroundStyle(.orange)
                }
                Divider()
                HStack {
                    Text("Success Rate:")
                    Spacer()
                    Text(String(format: "%.1f%%", summary.successRate * 100))
                        .bold()
                }
            }
            .font(.caption)
        }
    }

    // MARK: - File Pickers

    private func chooseBatchInput() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        // Use the extension from ConversionType
        panel.allowedContentTypes = [.init(filenameExtension: vm.conversionType.inputExtension)!]
        panel.message = "Select one or more \(vm.conversionType.inputExtension.uppercased()) files to convert"

        if panel.runModal() == .OK {
            vm.addBatchFiles(panel.urls)
        }
    }

    private func chooseBatchOutputDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose output directory for converted files"

        if panel.runModal() == .OK {
            vm.updateBatchOutputDirectory(panel.url)
        }
    }
}
