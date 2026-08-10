//  SingleModeView.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

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

                    if let warning = vm.formatWarning {
                        FormatWarningView(message: warning)
                    }
                    if let advisory = vm.advisoryNote {
                        FormatWarningView(message: advisory, isAdvisory: true)
                    }
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
                .disabled(vm.isRunning || vm.inputURL == nil || vm.outputURL == nil || !vm.chdmanVerified || !vm.canRun)

                if vm.isRunning {
                    Button(role: .destructive) {
                        vm.cancel()
                    } label: {
                        Label(vm.isCancelling ? "Stopping..." : "Stop", systemImage: "stop.fill")
                    }
                    .disabled(vm.isCancelling)
                }

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

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Deliver on the next tick: runModal() spins a nested run loop inside the button action,
        // so publishing as it unwinds still counts as mid-update.
        DispatchQueue.main.async { vm.inputURL = url }
    }

    private func chooseOutput() {
        let panel = NSSavePanel()

        // Use the extension from ConversionType
        let ext = vm.conversionType.outputExtension
        panel.allowedContentTypes = [.init(filenameExtension: ext)!]
        panel.nameFieldStringValue = suggestedOutputName(ext: ext)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        DispatchQueue.main.async { vm.outputURL = url }
    }

    private func suggestedOutputName(ext: String) -> String {
        if let input = vm.inputURL {
            return input.deletingPathExtension().lastPathComponent + "." + ext
        }
        return "output." + ext
    }
}
