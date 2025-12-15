import Foundation

/// A class responsible for running the chdman command-line tool asynchronously,
/// capturing and parsing its progress output, and reporting progress updates.
final class SwiftCHDTask {
    /// Launches the `chdman` tool with given arguments and streams progress.
    ///
    /// - Parameters:
    ///   - chdmanPath: Absolute path to the chdman executable. If just "chdman", relies on PATH.
    ///   - arguments: Full argument vector, e.g. ["createcd", "-i", input, "-o", output, ...]
    ///   - onProgress: Called with percentage 0.0...1.0 and the latest status line.
    ///
    /// - Throws: Error if the process fails to start or exits non-zero.
    func run(chdmanPath: String, arguments: [String], onProgress: @escaping (Double, String) -> Void) async throws {
        let process = Process()

        // Set up the executable URL
        let executableURL = URL(fileURLWithPath: chdmanPath)

        // Verify the executable exists and is accessible
        guard FileManager.default.isExecutableFile(atPath: chdmanPath) else {
            throw NSError(domain: "SwiftCHDTask", code: -1,
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

        // A serial queue to synchronize progress parsing and reporting
        let progressQueue = DispatchQueue(label: "swiftchd.progress.queue")

        // Thread-safe wrapper for collecting output
        let outputCollector = OutputCollector()

        // Internal handler to parse and report progress lines from stdout/stderr
        func processData(_ data: Data) {
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            // chdman may output multiple lines at once; split and parse each line
            text.split(separator: "\n", omittingEmptySubsequences: false).forEach { lineSub in
                let line = String(lineSub)
                outputCollector.append(line)

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

        // Await process termination asynchronously
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

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
                        domain: "SwiftCHDTask",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: errorMsg]
                    ))
                }
            }
        }
    }

    /// Runs a batch conversion operation
    ///
    /// - Parameters:
    ///   - chdmanPath: Absolute path to the chdman executable
    ///   - items: Array of batch items to process
    ///   - conversionType: The type of conversion to perform
    ///   - options: Additional SwiftCHD options to apply
    ///   - config: Batch configuration settings
    ///   - onItemUpdate: Called when an item's status changes
    ///   - onItemProgress: Called with progress updates for individual items
    /// - Returns: A BatchSummary with the results
    /// - Throws: Error if batch processing fails
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

            // Build arguments for this item
            var args: [String] = []
            args.append(conversionType.chdmanCommand)
            args += ["-i", item.inputURL.path(percentEncoded: false)]
            args += ["-o", item.outputURL.path(percentEncoded: false)]

            // Add additional options
            for opt in options where opt.isEnabled {
                let lower = opt.key.lowercased()
                if lower == "-i" || lower == "-o" { continue }
                args += opt.asArguments
            }

            // Run the conversion
            do {
                try await run(chdmanPath: chdmanPath, arguments: args) { pct, status in
                    onItemProgress(item.id, pct, status)
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

                // Stop on error if configured
                if config.stopOnError {
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

    /// Attempts to parse a percentage from typical chdman output lines like " 23% complete...".
    ///
    /// - Parameter line: A single line of output from chdman.
    /// - Returns: A value between 0.0 and 1.0 representing progress, or nil if not found.
    static func parsePercent(line: String) -> Double? {
        // Find a number followed by %
        // Matches up to 3 digits to cover 0-100%
        let pattern = #"(\d{1,3})%"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            let numberPart = line[range].replacingOccurrences(of: "%", with: "")
            if let value = Double(numberPart) {
                return min(max(value / 100.0, 0.0), 1.0)
            }
        }
        return nil
    }
}

// MARK: - Output Collector

/// Thread-safe wrapper for collecting output lines
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _output: [String] = []

    nonisolated func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        _output.append(line)
    }

    nonisolated func getLastLines(_ count: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_output.suffix(count))
    }
}
