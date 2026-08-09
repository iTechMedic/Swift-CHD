//  SwiftCHDTask.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation

/// A class responsible for running the chdman command-line tool asynchronously,
/// capturing and parsing its progress output, and reporting progress updates.
nonisolated final class SwiftCHDTask: @unchecked Sendable {

    static let errorDomain = "SwiftCHDTask"

    enum ErrorCode: Int {
        case executableNotFound = -1
        case cancelled = -2
        case unsupportedInput = -3
        case stalled = -4
    }

    /// Guards `currentProcess` and `cancelRequested`, both of which are touched from the
    /// caller's thread (via `cancel()`) and from the output-reading queue.
    private let stateLock = NSLock()
    private var currentProcess: Process?
    private var cancelRequested = false

    // MARK: - Cancellation

    /// Clears any prior cancellation. Call once before starting a run or a batch - `run()`
    /// deliberately does not reset the flag itself, so cancelling between batch items sticks.
    func resetCancellation() {
        stateLock.lock()
        defer { stateLock.unlock() }
        cancelRequested = false
    }

    var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelRequested
    }

    /// Requests cancellation and terminates any chdman process currently running.
    func cancel() {
        stateLock.lock()
        cancelRequested = true
        let process = currentProcess
        stateLock.unlock()

        guard let process, process.isRunning else { return }
        Self.terminate(process)
    }

    /// Records `process` as the one `cancel()` should act on. Synchronous and separate from the
    /// async `run()` because NSLock must not be held across an await.
    /// - Returns: true if cancellation was already requested and the caller must kill it.
    private func adoptRunningProcess(_ process: Process) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        currentProcess = process
        return cancelRequested
    }

    /// Forgets `process` once it has exited, so a later `cancel()` cannot signal a dead PID.
    private func releaseProcess(_ process: Process) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if currentProcess === process { currentProcess = nil }
    }

    /// SIGTERM, escalating to SIGKILL if chdman is wedged and does not go away.
    private static func terminate(_ process: Process) {
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    // MARK: - Input preparation

    /// Rewrites an input chdman cannot read - only DiscJuggler images today - into one it can.
    /// Runs off the calling actor since it copies the whole disc, and polls `isCancelled`.
    /// - Returns: The input to hand chdman, plus scratch for `CommandBuilder.cleanUp` to remove.
    func prepareInput(
        _ inputURL: URL,
        conversionType: ConversionType,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> CommandBuilder.PreparedInput {
        guard CommandBuilder.requiresStaging(inputURL, conversionType: conversionType) else {
            return .asIs(inputURL)
        }
        if isCancelled { throw Self.cancellationError() }

        let share = CommandBuilder.cdiStagingProgressShare

        return try await Task.detached(priority: .userInitiated) { [self] in
            do {
                let image = try CDIImage.read(at: inputURL)
                onProgress(0, "DiscJuggler image: \(image.tracks.count) tracks in "
                              + "\(image.sessionCount) session\(image.sessionCount == 1 ? "" : "s")")

                let staged = try CDIStager.stage(
                    image,
                    from: inputURL,
                    progress: { fraction in
                        onProgress(fraction * share,
                                   "Preparing tracks for chdman... \(Int(fraction * 100))% complete")
                    },
                    isCancelled: { self.isCancelled }
                )

                return CommandBuilder.PreparedInput(url: staged.gdiURL,
                                                    scratch: [staged.directory],
                                                    progressFloor: share)
            } catch CDIError.cancelled {
                throw Self.cancellationError()
            } catch let error as CDIError {
                throw NSError(
                    domain: Self.errorDomain,
                    code: ErrorCode.unsupportedInput.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: error.errorDescription ?? "\(error)"]
                )
            }
        }.value
    }

    // MARK: - Running chdman

    /// Launches chdman and streams progress, calling `onProgress` with a fraction 0...1 - or -1
    /// when the line carries no percentage - and the latest output line.
    func run(chdmanPath: String, arguments: [String], onProgress: @escaping (Double, String) -> Void) async throws {
        if isCancelled { throw Self.cancellationError() }

        let process = Process()

        // Set up the executable URL
        let executableURL = URL(fileURLWithPath: chdmanPath)

        // Verify the executable exists and is accessible
        guard FileManager.default.isExecutableFile(atPath: chdmanPath) else {
            throw NSError(domain: Self.errorDomain, code: ErrorCode.executableNotFound.rawValue,
                         userInfo: [NSLocalizedDescriptionKey: "chdman executable not found or not accessible at: \(chdmanPath)"])
        }

        process.executableURL = executableURL
        process.arguments = arguments

        // Set environment to include common paths
        var env = ProcessInfo.processInfo.environment
        if let existingPath = env["PATH"] {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        } else {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // A GUI app has no terminal, so a child that ever reads stdin would block forever on a
        // descriptor that never yields input. Point it at /dev/null so any read sees EOF at once.
        process.standardInput = FileHandle.nullDevice

        // A serial queue to synchronize progress parsing and reporting
        let progressQueue = DispatchQueue(label: "swiftchd.progress.queue")

        // Thread-safe wrapper for collecting output
        let outputCollector = OutputCollector()
        // Set when we kill chdman ourselves, so the non-zero exit is reported as the real
        // cause rather than a bare "exit code 15".
        let abort = AbortReasonBox()

        // Internal handler to parse and report progress lines from stdout/stderr
        func processData(_ data: Data) {
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            // chdman may output multiple lines at once; split and parse each line
            text.split(separator: "\n", omittingEmptySubsequences: false).forEach { lineSub in
                let line = String(lineSub)
                outputCollector.append(line)

                // Watchdog: bail out of a run chdman will never finish.
                if let reason = Self.stallReason(for: line), abort.set(reason) {
                    Self.terminate(process)
                }

                if let pct = Self.parsePercent(line: line) {
                    onProgress(pct, line)
                } else {
                    // Use -1 to indicate progress unknown, just forward the line
                    onProgress(-1, line)
                }
            }
        }

        // Set readability handlers to read stdout and stderr asynchronously
        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            progressQueue.async { processData(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            progressQueue.async { processData(data) }
        }

        try process.run()

        // cancel() may have landed between the isCancelled check and process.run(), in which
        // case it saw no process to kill. Catch that here.
        if adoptRunningProcess(process) { Self.terminate(process) }

        // Await process termination asynchronously
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                self?.releaseProcess(proc)

                if self?.isCancelled == true {
                    continuation.resume(throwing: Self.cancellationError())
                    return
                }

                if let reason = abort.reason {
                    continuation.resume(throwing: NSError(
                        domain: Self.errorDomain,
                        code: ErrorCode.stalled.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: reason]
                    ))
                    return
                }

                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let code = Int(proc.terminationStatus)

                    // Get the last few lines of output for context
                    let lastLines = outputCollector.getLastLines(5)
                    let errorContext = lastLines.joined(separator: "\n")
                    let errorMsg = errorContext.isEmpty ?
                        "chdman exited with code \(code)" :
                        "chdman error (exit code \(code)):\n\(errorContext)"

                    continuation.resume(throwing: NSError(
                        domain: Self.errorDomain,
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: errorMsg]
                    ))
                }
            }
        }
    }

    /// Converts `items` in order, reporting each one's status and progress as it goes.
    func runBatch(
        chdmanPath: String,
        items: [BatchConversionItem],
        conversionType: ConversionType,
        options: [SwiftCHDOption],
        config: BatchConversionConfig,
        onItemUpdate: @escaping (BatchConversionItem) -> Void,
        onItemProgress: @escaping (UUID, Double, String) -> Void
    ) async throws -> BatchSummary {
        var succeeded = 0
        var failed = 0
        var skipped = 0

        for var item in items {
            if isCancelled { break }

            // Reject input chdman cannot read before launching it, so an unconvertible file
            // fails fast with an explanation instead of stalling the whole queue behind it.
            if let reason = InputValidator.rejectionReason(for: item.inputURL, conversionType: conversionType) {
                item.status = .failed
                item.errorMessage = reason
                failed += 1
                onItemUpdate(item)
                if config.stopOnError { break }
                continue
            }

            // Check if we should skip existing files
            if config.skipExisting && FileManager.default.fileExists(atPath: item.outputURL.path(percentEncoded: false)) {
                item.status = .skipped
                item.errorMessage = "Output file already exists"
                skipped += 1
                onItemUpdate(item)
                continue
            }

            // Update status to processing
            item.status = .processing
            item.progress = 0
            onItemUpdate(item)

            // Run the conversion
            do {
                // Staging happens per item rather than up front: a queue of CDIs would otherwise
                // need every disc on disk at once, instead of one at a time.
                let itemID = item.id
                let prepared = try await prepareInput(item.inputURL, conversionType: conversionType) { pct, status in
                    onItemProgress(itemID, pct, status)
                }

                let command = CommandBuilder.command(for: conversionType,
                                                     input: prepared,
                                                     output: item.outputURL,
                                                     options: options)
                defer { CommandBuilder.cleanUp(command) }

                try await run(chdmanPath: chdmanPath, arguments: command.arguments) { pct, status in
                    onItemProgress(itemID, pct >= 0 ? command.overallProgress(pct) : pct, status)
                }

                // Success
                item.status = .completed
                item.progress = 1.0
                succeeded += 1
                onItemUpdate(item)
            } catch {
                // Failure
                item.status = .failed
                item.errorMessage = error.localizedDescription
                failed += 1
                onItemUpdate(item)

                // Stop on error if configured, and always stop when the user cancelled.
                if config.stopOnError || isCancelled {
                    break
                }
            }
        }

        return BatchSummary(
            total: items.count,
            succeeded: succeeded,
            failed: failed,
            skipped: skipped
        )
    }

    // MARK: - Output parsing

    /// Recognises a state chdman never leaves: unparseable input gives `Input tracks: 0`, then
    /// `nan%` forever. Both share one message - they arrive on different pipes, either first.
    /// - Returns: A user-facing explanation, or nil if the line looks healthy.
    static func stallReason(for line: String) -> String? {
        guard line.contains("Input tracks: 0") || line.contains("nan%") else { return nil }
        return """
            chdman could not read the input as a CD image.

            It found no tracks and zero length, then began reporting "nan% complete" - a state \
            it never leaves. The conversion was stopped; left running, chdman would spin \
            forever and leave behind an empty CHD.

            Check that the input is a valid CD image in a format chdman supports (.cue, .gdi, \
            .iso, .toc, .nrg, .cdr), or a DiscJuggler (.cdi) image, which Swift-CHD converts \
            for it.
            """
    }

    /// Parses progress from lines like "23.4% complete". Only a percentage followed by "complete"
    /// counts: the closing `... final ratio = 61.3%` would otherwise read as a jump backwards.
    /// - Returns: Progress 0.0...1.0, or nil if the line carries none.
    static func parsePercent(line: String) -> Double? {
        let pattern = #"(\d{1,3}(?:\.\d+)?)%\s*complete"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }

        let digits = line[range].prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { return nil }
        return min(max(value / 100.0, 0.0), 1.0)
    }

    private static func cancellationError() -> NSError {
        NSError(domain: errorDomain, code: ErrorCode.cancelled.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Conversion cancelled."])
    }
}

// MARK: - Output Collector

/// Thread-safe wrapper for collecting output lines
nonisolated private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _output: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        _output.append(line)
    }

    func getLastLines(_ count: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_output.suffix(count))
    }
}

// MARK: - Abort Reason

/// Thread-safe single-assignment box recording why we killed chdman.
nonisolated private final class AbortReasonBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _reason: String?

    /// Stores `reason` if none is set yet.
    /// - Returns: true if this call was the one that set it, so the caller kills exactly once.
    func set(_ reason: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard _reason == nil else { return false }
        _reason = reason
        return true
    }

    var reason: String? {
        lock.lock()
        defer { lock.unlock() }
        return _reason
    }
}
