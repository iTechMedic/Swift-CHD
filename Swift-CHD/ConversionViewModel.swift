//  ConversionViewModel.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation
import Combine

@MainActor
final class ConversionViewModel: ObservableObject {
    // MARK: - Conversion Mode
    @Published var isBatchMode: Bool = false

    // MARK: - Single File Mode
    @Published var conversionType: ConversionType = .isoToChd {
        didSet {
            guard oldValue != conversionType else { return }
            resetForNewConversionType()
        }
    }

    @Published var inputURL: URL? {
        didSet {
            if let inputURL {
                outputURL = defaultOutputURL(for: inputURL)
            }
            refreshFileWarning()
        }
    }
    @Published var outputURL: URL?

    // MARK: - Batch Mode
    @Published var batchItems: [BatchConversionItem] = []
    @Published var batchConfig = BatchConversionConfig()
    @Published var batchOutputDirectory: URL?
    @Published var batchSummary: BatchSummary?

    // MARK: - Common Settings
    @Published var chdmanPath: String = "chdman"
    @Published var options: [SwiftCHDOption] = []
    @Published var advancedMode: Bool = false {
        didSet {
            guard oldValue != advancedMode else { return }
            resetOptionsForType()
        }
    }

    @Published var progress: Double = 0
    @Published var statusLine: String = ""
    @Published var isRunning: Bool = false
    @Published var errorMessage: String?
    @Published var consoleOutput: String = ""

    @Published var selectedKnownOptionKey: String = "-c"
    @Published var chdmanVerified: Bool = false
    @Published var chdmanNotFoundHelp: String? = nil

    /// Result of the asynchronous per-file readability check. Written only when a detached
    /// check completes, never synchronously from a view-driven `didSet`.
    @Published private var fileWarning: String? = nil

    /// How the current file will be converted, when that is worth saying. Advisory only.
    @Published private var fileAdvisory: String? = nil

    /// Invalidates in-flight file checks so a slow one cannot overwrite a newer selection.
    private var fileWarningToken = 0

    /// A note about the conversion that does not stop it running. Suppressed while a rejection is
    /// showing, so the user is never given advice about a file that is not going to convert.
    var advisoryNote: String? {
        guard formatWarning == nil, !isBatchMode else { return nil }
        return fileAdvisory
    }

    /// Why the current conversion cannot run; non-nil disables the Run button. Only gates Single
    /// mode - Batch fails unreadable files individually so one cannot block the queue.
    var formatWarning: String? {
        if case let .unsupported(reason, guidance) = conversionType.chdmanSupport {
            return "\(reason)\n\n\(guidance)"
        }
        return isBatchMode ? nil : fileWarning
    }

    /// True once a run has been asked to stop, until it actually does.
    @Published var isCancelling: Bool = false

    private let task = SwiftCHDTask()

    /// Whether a conversion can be started at all, ignoring path/verification state.
    var canRun: Bool { formatWarning == nil }

    init() {
        resetOptionsForType()

        // Kick off verification via Swift Concurrency
        Task {
            await verifyCHDMan()
        }
    }

    // Each assignment is guarded because @Published republishes even when unchanged, and a burst
    // of those turns one stray update into a screenful of "Publishing changes" faults.
    func resetForNewConversionType() {
        // Reset options to defaults for the new conversion type
        resetOptionsForType()

        // Clear all file selections
        if inputURL != nil { inputURL = nil }
        if outputURL != nil { outputURL = nil }

        // Clear batch items and settings
        if !batchItems.isEmpty { batchItems.removeAll() }
        if batchOutputDirectory != nil { batchOutputDirectory = nil }
        if batchSummary != nil { batchSummary = nil }

        // Clear console output and status
        if !consoleOutput.isEmpty { consoleOutput = "" }
        if errorMessage != nil { errorMessage = nil }
        if !statusLine.isEmpty { statusLine = "" }
        if progress != 0 { progress = 0 }

        refreshFileWarning()
    }

    /// Re-runs the per-file readability check for the current selection.
    private func refreshFileWarning() {
        fileWarningToken &+= 1
        let token = fileWarningToken
        if fileWarning != nil { fileWarning = nil }
        if fileAdvisory != nil { fileAdvisory = nil }

        guard let url = inputURL else { return }

        // Inspecting the file touches disk, so keep it off the main actor - a stalled network
        // volume should never freeze the UI just because a file was selected.
        let type = conversionType
        Task { [weak self] in
            let result = await Task.detached { () -> (String?, String?) in
                if let reason = InputValidator.rejectionReason(for: url, conversionType: type) {
                    return (reason, nil)
                }
                return (nil, InputValidator.advisory(for: url, conversionType: type))
            }.value
            guard let self, token == self.fileWarningToken else { return }
            self.fileWarning = result.0
            self.fileAdvisory = result.1
        }
    }

    func resetOptionsForType() {
        let updated = advancedMode ? conversionType.advancedOptions : conversionType.defaultOptions
        if updated != options { options = updated }
    }

    func addSelectedOption() {
        let list = ConversionType.knownOptions[conversionType] ?? []
        guard let match = list.first(where: { $0.0 == selectedKnownOptionKey }) else { return }
        let opt = SwiftCHDOption(key: match.0, value: match.1, help: match.2, type: match.3)
        // Avoid duplicates by key
        if !options.contains(where: { $0.key == opt.key }) {
            options.append(opt)
        }
    }

    func verifyCHDMan() async {
        // Run verification off the main actor to avoid blocking
        var path = chdmanPath.trimmingCharacters(in: .whitespaces)

        // Auto-correct if user just entered a directory path
        if path.hasSuffix("/bin") || path.hasSuffix("/bin/") {
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chdman"
        }

        let (foundPath, helpText, verified) = await Task.detached {
            var foundPath: String? = nil
            var helpText: String? = nil
            var verified = false

            // If path is absolute and exists
            if path.hasPrefix("/") {
                if FileManager.default.isExecutableFile(atPath: path) {
                    foundPath = path
                    verified = true
                }
            }

            if !verified {
                // Check common Homebrew locations
                let candidates = [
                    "/opt/homebrew/bin/chdman", // Apple Silicon
                    "/usr/local/bin/chdman"     // Intel
                ]
                for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
                    foundPath = c
                    verified = true
                    break
                }
            }

            if !verified {
                // Try PATH lookup via /usr/bin/env bash to get proper shell environment
                let bash = Process()
                bash.executableURL = URL(fileURLWithPath: "/bin/bash")
                bash.arguments = ["-l", "-c", "which chdman"]
                let pipe = Pipe()
                bash.standardOutput = pipe
                bash.standardError = Pipe() // Suppress errors
                do {
                    try bash.run()
                    bash.waitUntilExit()
                    if bash.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !str.isEmpty, FileManager.default.isExecutableFile(atPath: str) {
                            foundPath = str
                            verified = true
                        }
                    }
                } catch { }
            }

            if !verified {
                helpText = """
                chdman was not found in the system PATH.

                If you have Homebrew installed:

                1. Open Terminal and run:
                   brew install mame

                2. After installation, chdman should be at:
                   - Apple Silicon: /opt/homebrew/bin/chdman
                   - Intel Mac: /usr/local/bin/chdman

                3. Click the "Verify" button again, or manually enter the full path above.

                If you don't have Homebrew:

                1. Install Homebrew first:
                   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

                2. Then install MAME (which includes chdman):
                   brew install mame
                """
            }

            return (foundPath, helpText, verified)
        }.value

        // Publish results (already on MainActor due to function isolation)
        self.chdmanNotFoundHelp = helpText
        if let foundPath {
            self.chdmanPath = foundPath
        }
        self.chdmanVerified = verified
    }

    /// Defaults Single File mode's output to the same folder as the input file, mirroring
    /// Batch mode's "same as input files" default (see `generateOutputURL`).
    private func defaultOutputURL(for inputURL: URL) -> URL {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let ext = conversionType.outputExtension
        return inputURL.deletingLastPathComponent().appendingPathComponent("\(baseName).\(ext)")
    }

    /// Validates the selection and builds the chdman invocation. Async because a DiscJuggler
    /// input is staged first, off the main actor, reporting through `onProgress`.
    func buildCommand(onProgress: @escaping @Sendable (Double, String) -> Void = { _, _ in }) async throws -> ConversionCommand {
        guard let inputURL, let outputURL else {
            throw NSError(domain: "Swift-CHD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please select input and output paths."])
        }

        // Reject input chdman cannot read before launching it. Without this, an unreadable
        // image leaves chdman looping on "nan% complete" with no way out but force-quitting.
        if let reason = InputValidator.rejectionReason(for: inputURL, conversionType: conversionType) {
            throw NSError(domain: SwiftCHDTask.errorDomain,
                          code: SwiftCHDTask.ErrorCode.unsupportedInput.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: reason])
        }

        let prepared = try await task.prepareInput(inputURL,
                                                   conversionType: conversionType,
                                                   onProgress: onProgress)

        return CommandBuilder.command(for: conversionType,
                                      input: prepared,
                                      output: outputURL,
                                      options: options)
    }

    func start() async {
        task.resetCancellation()
        isCancelling = false

        if isBatchMode {
            await startBatch()
        } else {
            await startSingle()
        }
    }

    /// Stops the running conversion, killing the chdman process.
    func cancel() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        statusLine = "Cancelling..."
        task.cancel()
    }

    /// True when an error represents a user-requested cancellation rather than a failure.
    private func isCancellation(_ error: NSError) -> Bool {
        error.domain == SwiftCHDTask.errorDomain
            && error.code == SwiftCHDTask.ErrorCode.cancelled.rawValue
    }

    // MARK: - Batch Mode Operations

    func addBatchFiles(_ urls: [URL]) {
        for url in urls {
            // Generate output URL based on conversion type
            let outputURL = generateOutputURL(for: url)
            let item = BatchConversionItem(inputURL: url, outputURL: outputURL)

            // Avoid duplicates
            if !batchItems.contains(where: { $0.inputURL == url }) {
                batchItems.append(item)
            }
        }
    }

    func removeBatchItem(_ item: BatchConversionItem) {
        batchItems.removeAll { $0.id == item.id }
    }

    func clearBatchItems() {
        batchItems.removeAll()
        batchSummary = nil
    }

    func generateOutputURL(for inputURL: URL) -> URL {
        let baseDir: URL
        if let batchOutputDir = batchOutputDirectory {
            baseDir = batchOutputDir
        } else {
            baseDir = inputURL.deletingLastPathComponent()
        }

        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let newExtension = conversionType.outputExtension
        return baseDir.appendingPathComponent("\(baseName).\(newExtension)")
    }

    func updateBatchOutputDirectory(_ url: URL?) {
        batchOutputDirectory = url
        // Update all existing items' output URLs
        for index in batchItems.indices {
            batchItems[index].outputURL = generateOutputURL(for: batchItems[index].inputURL)
        }
    }

    private func startBatch() async {
        guard !isRunning else { return }
        guard !batchItems.isEmpty else {
            errorMessage = "No files added for batch conversion"
            return
        }

        isRunning = true
        progress = 0
        errorMessage = nil
        batchSummary = nil

        // Initialize console output
        consoleOutput = "=== BATCH CONVERSION STARTED ===\n"
        consoleOutput += "Mode: \(conversionType.title)\n"
        consoleOutput += "Files: \(batchItems.count)\n"
        consoleOutput += String(repeating: "=", count: 60) + "\n\n"

        do {
            let summary = try await task.runBatch(
                chdmanPath: chdmanPath,
                items: batchItems,
                conversionType: conversionType,
                options: options,
                config: batchConfig
            ) { [weak self] updatedItem in
                // Update item in list
                Task { @MainActor in
                    guard let self = self else { return }
                    if let index = self.batchItems.firstIndex(where: { $0.id == updatedItem.id }) {
                        self.batchItems[index] = updatedItem

                        // Log to console
                        let fileName = updatedItem.inputURL.lastPathComponent
                        switch updatedItem.status {
                        case .processing:
                            self.consoleOutput += "Processing: \(fileName)\n"
                        case .completed:
                            self.consoleOutput += "Completed: \(fileName)\n"
                        case .failed:
                            self.consoleOutput += "Failed: \(fileName)\n"
                            if let error = updatedItem.errorMessage {
                                self.consoleOutput += "   Error: \(error)\n"
                            }
                        case .skipped:
                            self.consoleOutput += "Skipped: \(fileName)\n"
                            if let reason = updatedItem.errorMessage {
                                self.consoleOutput += "   Reason: \(reason)\n"
                            }
                        case .pending:
                            break
                        }
                        self.consoleOutput += "\n"
                    }

                    // Update overall progress
                    let completed = self.batchItems.filter {
                        $0.status == .completed || $0.status == .failed || $0.status == .skipped
                    }.count
                    self.progress = Double(completed) / Double(self.batchItems.count)
                }
            } onItemProgress: { [weak self] itemID, pct, status in
                // Update progress for specific item
                Task { @MainActor in
                    guard let self = self else { return }
                    if let index = self.batchItems.firstIndex(where: { $0.id == itemID }) {
                        self.batchItems[index].progress = pct
                    }
                    self.statusLine = status
                }
            }

            batchSummary = summary
            let wasCancelled = isCancelling
            consoleOutput += String(repeating: "=", count: 60) + "\n"
            consoleOutput += wasCancelled ? "=== BATCH CONVERSION CANCELLED ===\n" : "=== BATCH CONVERSION COMPLETED ===\n"
            consoleOutput += summary.description + "\n"
            statusLine = wasCancelled
                ? "Batch cancelled after \(summary.succeeded)/\(summary.total)"
                : "Batch completed: \(summary.succeeded)/\(summary.total) succeeded"

        } catch let error as NSError {
            if isCancellation(error) {
                consoleOutput += String(repeating: "=", count: 60) + "\n"
                consoleOutput += "BATCH CANCELLED\n"
                statusLine = "Batch cancelled"
            } else {
                errorMessage = "Batch conversion error: \(error.localizedDescription)"
                consoleOutput += String(repeating: "=", count: 60) + "\n"
                consoleOutput += "BATCH ERROR: \(error.localizedDescription)\n"
            }
        }

        isRunning = false
        isCancelling = false
    }

    private func startSingle() async {
        guard !isRunning else { return }

        // Snapshot the URLs in use for this run so security-scoped access start/stop stays
        // balanced even if inputURL/outputURL are reset to nil after a successful conversion.
        let runInputURL = inputURL
        let runOutputURL = outputURL
        var didSucceed = false

        // Store whether we started accessing resources
        var inputStarted = false
        var outputStarted = false
        var inputDirStarted = false
        var outputDirStarted = false

        do {
            // Start accessing security-scoped resources for files
            if let runInputURL {
                inputStarted = runInputURL.startAccessingSecurityScopedResource()
                // Also try to get access to parent directory
                let inputDir = runInputURL.deletingLastPathComponent()
                inputDirStarted = inputDir.startAccessingSecurityScopedResource()
            }
            if let runOutputURL {
                outputStarted = runOutputURL.startAccessingSecurityScopedResource()
                // Also try to get access to parent directory
                let outputDir = runOutputURL.deletingLastPathComponent()
                outputDirStarted = outputDir.startAccessingSecurityScopedResource()
            }

            // Set running *before* building the command: a DiscJuggler input is rewritten as
            // part of that, which is slow enough to need a progress bar and a working Cancel.
            isRunning = true
            progress = 0
            statusLine = "Starting..."
            errorMessage = nil
            consoleOutput = ""

            let command = try await buildCommand { [weak self] pct, line in
                guard let self else { return }
                Task { @MainActor in
                    if pct >= 0 { self.progress = pct }
                    self.statusLine = line
                    if !line.isEmpty { self.consoleOutput += line + "\n" }
                }
            }
            defer { CommandBuilder.cleanUp(command) }
            let args = command.arguments

            let cmdLine = "\(chdmanPath) \(args.joined(separator: " "))"
            consoleOutput += "$ \(cmdLine)\n"
            consoleOutput += String(repeating: "=", count: 60) + "\n"

            try await task.run(chdmanPath: chdmanPath, arguments: args) { [weak self] pct, line in
                Task { @MainActor in
                    if pct >= 0 { self?.progress = command.overallProgress(pct) }
                    self?.statusLine = line

                    // Append to console output
                    if !line.isEmpty {
                        self?.consoleOutput += line + "\n"
                    }
                }
            }

            statusLine = "Conversion completed successfully!"
            consoleOutput += String(repeating: "=", count: 60) + "\n"
            consoleOutput += "SUCCESS: Conversion completed!\n"
            progress = 1.0
            didSucceed = true
        } catch let error as NSError where isCancellation(error) {
            consoleOutput += String(repeating: "=", count: 60) + "\n"
            consoleOutput += "CANCELLED: conversion stopped by user.\n"
            statusLine = "Cancelled"
            progress = 0
        } catch let error as NSError {
            // Log error to console
            consoleOutput += String(repeating: "=", count: 60) + "\n"
            consoleOutput += "ERROR: \(error.localizedDescription)\n"

            // Provide more helpful error messages
            let errorCode = error.code
            let errorDomain = error.domain

            if errorDomain == NSCocoaErrorDomain {
                switch errorCode {
                case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                    errorMessage = "Permission denied. Go to Xcode -> Target -> Signing & Capabilities -> Remove 'App Sandbox'."
                case NSFileNoSuchFileError:
                    errorMessage = "File not found. Please verify input file exists."
                case NSFileWriteFileExistsError:
                    errorMessage = "Output file already exists. Enable '-f' option to force overwrite."
                default:
                    errorMessage = "File error: \(error.localizedDescription)"
                }
            } else if errorDomain == SwiftCHDTask.errorDomain {
                switch SwiftCHDTask.ErrorCode(rawValue: errorCode) {
                case .executableNotFound:
                    errorMessage = error.localizedDescription + "\n\nMake sure the chdman path is correct (should end with /chdman)."
                case .unsupportedInput, .stalled:
                    // Already a full explanation aimed at the user.
                    errorMessage = error.localizedDescription
                default:
                    // The error already contains the chdman output
                    errorMessage = error.localizedDescription
                }
            } else if errorDomain == NSPOSIXErrorDomain && errorCode == 13 { // EACCES
                errorMessage = "Permission denied (POSIX error 13). Disable App Sandbox in Xcode."
            } else {
                errorMessage = error.localizedDescription
            }
        }

        // Always stop accessing resources when done
        if inputStarted, let runInputURL {
            runInputURL.stopAccessingSecurityScopedResource()
        }
        if outputStarted, let runOutputURL {
            runOutputURL.stopAccessingSecurityScopedResource()
        }
        if inputDirStarted, let runInputURL {
            runInputURL.deletingLastPathComponent().stopAccessingSecurityScopedResource()
        }
        if outputDirStarted, let runOutputURL {
            runOutputURL.deletingLastPathComponent().stopAccessingSecurityScopedResource()
        }

        // Reset selections after a successful conversion so the next file picked gets a
        // fresh "same as input file" output default (console/progress are left as-is).
        if didSucceed {
            inputURL = nil
            outputURL = nil
        }

        isRunning = false
        isCancelling = false
    }
}
