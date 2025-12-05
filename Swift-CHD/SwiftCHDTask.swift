import Foundation

// MARK: - Batch Conversion Support

/// Represents a single file in a batch conversion operation
struct BatchConversionItem: Identifiable, Hashable {
    let id = UUID()
    let inputURL: URL
    var outputURL: URL
    var status: BatchItemStatus = .pending
    var progress: Double = 0.0
    var errorMessage: String?
    
    // For Hashable conformance
    static func == (lhs: BatchConversionItem, rhs: BatchConversionItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Status of an individual batch item
enum BatchItemStatus: String {
    case pending = "Pending"
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"
    case skipped = "Skipped"
    
    var icon: String {
        switch self {
        case .pending: return "circle"
        case .processing: return "arrow.trianglehead.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "arrow.uturn.right.circle"
        }
    }
    
    var color: String {
        switch self {
        case .pending: return "gray"
        case .processing: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .skipped: return "orange"
        }
    }
}

/// Configuration for batch operations
struct BatchConversionConfig {
    var skipExisting: Bool = true
    var stopOnError: Bool = false
    var maxConcurrent: Int = 1 // Number of simultaneous conversions
    var outputDirectory: URL?
    var preserveDirectoryStructure: Bool = false
}

/// Summary of a completed batch conversion
struct BatchSummary: CustomStringConvertible {
    var total: Int
    var succeeded: Int
    var failed: Int
    var skipped: Int
    
    /// Success rate as a value between 0.0 and 1.0
    var successRate: Double {
        guard total > 0 else { return 0.0 }
        return Double(succeeded) / Double(total)
    }
    
    var description: String {
        """
        Total: \(total)
        Succeeded: \(succeeded)
        Failed: \(failed)
        Skipped: \(skipped)
        """
    }
}

/// Option type to determine UI representation
enum SwiftCHDOptionType: Hashable {
    case flag // Simple flag with no value (e.g., -f)
    case text // Free text input
    case dropdown([String]) // Dropdown with predefined choices
}

struct SwiftCHDOption: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String?
    var help: String
    var type: SwiftCHDOptionType = .text
    var isEnabled: Bool = true

    var asArguments: [String] {
        if let value, !value.isEmpty {
            return [key, value]
        } else if type == .flag {
            // Flag-only options (like -f) have no value
            return [key]
        } else {
            return []
        }
    }
    
    // For Hashable conformance
    static func == (lhs: SwiftCHDOption, rhs: SwiftCHDOption) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ConversionType: String, CaseIterable, Identifiable {
    case isoToChd
    case cueToChd
    case gdiToChd
    case chdToIso
    case chdToCue
    case chdToGdi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isoToChd: return "ISO → CHD"
        case .cueToChd: return "CUE → CHD"
        case .gdiToChd: return "GDI → CHD"
        case .chdToIso: return "CHD → ISO"
        case .chdToCue: return "CHD → CUE"
        case .chdToGdi: return "CHD → GDI"
        }
    }
    
    var description: String {
        switch self {
        case .isoToChd: return "Convert single-track ISO to compressed CHD"
        case .cueToChd: return "Convert BIN/CUE (multi-track) to CHD"
        case .gdiToChd: return "Convert Dreamcast GDI to CHD"
        case .chdToIso: return "Extract CHD to raw ISO"
        case .chdToCue: return "Extract CHD to BIN/CUE"
        case .chdToGdi: return "Extract CHD to Dreamcast GDI"
        }
    }
    
    var inputExtension: String {
        switch self {
        case .isoToChd: return "iso"
        case .cueToChd: return "cue"
        case .gdiToChd: return "gdi"
        case .chdToIso, .chdToCue, .chdToGdi: return "chd"
        }
    }
    
    var outputExtension: String {
        switch self {
        case .isoToChd, .cueToChd, .gdiToChd: return "chd"
        case .chdToIso: return "iso"
        case .chdToCue: return "cue"
        case .chdToGdi: return "gdi"
        }
    }
    
    var chdmanCommand: String {
        switch self {
        case .isoToChd, .cueToChd, .gdiToChd:
            return "createcd"
        case .chdToIso, .chdToCue, .chdToGdi:
            return "extractcd"
        }
    }

    // Start with minimal defaults - users enable what they need
    var defaultOptions: [SwiftCHDOption] {
        return []  // No options by default, cleaner starting point
    }
    
    // Compression codec descriptions
    static let codecDescriptions: [String: String] = [
        "cd": "Standard CD-ROM (recommended) - Best compatibility, fast compression",
        "cdlz": "CD-ROM + LZMA - Smaller size, slower compression, good for archival",
        "cdzl": "CD-ROM + Zlib - Balanced size/speed, good general purpose",
        "cdfl": "CD-ROM + FLAC - Best for audio-heavy games, preserves audio quality"
    ]
    
    // All available options for advanced users
    var advancedOptions: [SwiftCHDOption] {
        switch self {
        case .isoToChd, .cueToChd, .gdiToChd:
            return [
                SwiftCHDOption(key: "-c", value: "cd", help: "Compression codec", type: .dropdown(["cd", "cdlz", "cdzl", "cdfl"]), isEnabled: false),
                SwiftCHDOption(key: "-hs", value: "", help: "Hunk size in bytes (e.g., 2048, 4096)", type: .text, isEnabled: false),
                SwiftCHDOption(key: "-f", value: "", help: "Force overwrite existing files", type: .flag, isEnabled: false),
                SwiftCHDOption(key: "-v", value: "", help: "Verify after compression", type: .flag, isEnabled: false),
                SwiftCHDOption(key: "-np", value: "", help: "Proceed even if not perfect", type: .flag, isEnabled: false)
            ]
        case .chdToIso, .chdToCue, .chdToGdi:
            return [
                SwiftCHDOption(key: "-f", value: "", help: "Force overwrite existing files", type: .flag, isEnabled: false),
                SwiftCHDOption(key: "-v", value: "", help: "Verify after extraction", type: .flag, isEnabled: false),
                SwiftCHDOption(key: "-ob", value: "", help: "Output BIN filename", type: .text, isEnabled: false)
            ]
        }
    }
}

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
        final class OutputCollector: @unchecked Sendable {
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

// Notes:
// - chdman subcommands include: createcd, createhd, createav, copydata, extractcd, extracthd, etc.
// - You will map ConversionType to appropriate chdman subcommands and auto-fill -i/-o options.
// - Additional flags like -f (force overwrite), -v (verbose), -r (hunksize) can be exposed in the UI.
// - The SwiftCHDOption struct is designed to hold key-value pairs for chdman CLI options;
//   these can be converted into argument arrays when constructing the command line.
// - When implementing UI or higher-level logic, map ConversionType to subcommands (e.g., isoToChd → createcd),
//   set input/output files accordingly, and append user-selected options before running the task.
