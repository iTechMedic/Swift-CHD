import Foundation
import Foundation
import Combine

@MainActor
final class ConversionViewModel: ObservableObject {
    // MARK: - Conversion Mode
    @Published var isBatchMode: Bool = false
    
    // MARK: - Single File Mode
    @Published var conversionType: ConversionType = .isoToChd {
        didSet {
            resetOptionsForType()
        }
    }

    @Published var inputURL: URL?
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
            resetOptionsForType()
        }
    }

    @Published var progress: Double = 0
    @Published var statusLine: String = ""
    @Published var isRunning: Bool = false
    @Published var errorMessage: String?
    @Published var consoleOutput: String = ""

    // Known flags catalog per conversion type
    let knownOptions: [ConversionType: [(String, String?, String, SwiftCHDOptionType)]] = [
        .isoToChd: [
            ("-c", "cd", "Compression codec", .dropdown(["cd", "cdlz", "cdzl", "cdfl"])),
            ("-hs", "", "Hunk size in bytes", .text),
            ("-f", "", "Force overwrite", .flag),
            ("-np", "", "Proceed if not perfect", .flag)
        ],
        .cueToChd: [
            ("-c", "cd", "Compression codec", .dropdown(["cd", "cdlz", "cdzl", "cdfl"])),
            ("-hs", "", "Hunk size in bytes", .text),
            ("-f", "", "Force overwrite", .flag),
            ("-np", "", "Proceed if not perfect", .flag)
        ],
        .gdiToChd: [
            ("-c", "cd", "Compression codec", .dropdown(["cd", "cdlz", "cdzl", "cdfl"])),
            ("-hs", "", "Hunk size in bytes", .text),
            ("-f", "", "Force overwrite", .flag),
            ("-np", "", "Proceed if not perfect", .flag)
        ],
        .chdToIso: [
            ("-f", "", "Force overwrite", .flag)
        ],
        .chdToCue: [
            ("-f", "", "Force overwrite", .flag),
            ("-ob", "", "Output BIN filename", .text)
        ],
        .chdToGdi: [
            ("-f", "", "Force overwrite", .flag),
            ("-ob", "", "Output BIN filename", .text)
        ]
    ]

    @Published var selectedKnownOptionKey: String = "-c"
    @Published var chdmanVerified: Bool = false
    @Published var chdmanNotFoundHelp: String? = nil

    private let task = SwiftCHDTask()

    init() {
        resetOptionsForType()
        
        // Kick off verification via Swift Concurrency
        Task {
            await verifyCHDMan()
        }
    }

    func resetOptionsForType() {
        options = advancedMode ? conversionType.advancedOptions : conversionType.defaultOptions
    }

    func addSelectedOption() {
        let list = knownOptions[conversionType] ?? []
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
                   • Apple Silicon: /opt/homebrew/bin/chdman
                   • Intel Mac: /usr/local/bin/chdman
                
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

    func buildArguments() throws -> [String] {
        guard let inputURL, let outputURL else {
            throw NSError(domain: "Swift-CHD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please select input and output paths."])
        }

        var args: [String] = []
        
        // Use the chdmanCommand from ConversionType
        args.append(conversionType.chdmanCommand)

        // Base -i/-o - use path(percentEncoded: false) to get proper paths
        args += ["-i", inputURL.path(percentEncoded: false)]
        args += ["-o", outputURL.path(percentEncoded: false)]

        // Additional options from UI (skip -i/-o to avoid duplicates)
        for opt in options where opt.isEnabled {
            let lower = opt.key.lowercased()
            if lower == "-i" || lower == "-o" { continue }
            args += opt.asArguments
        }

        return args
    }

    func start() async {
        if isBatchMode {
            await startBatch()
        } else {
            await startSingle()
        }
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
                            self.consoleOutput += "▶️ Processing: \(fileName)\n"
                        case .completed:
                            self.consoleOutput += "✅ Completed: \(fileName)\n"
                        case .failed:
                            self.consoleOutput += "❌ Failed: \(fileName)\n"
                            if let error = updatedItem.errorMessage {
                                self.consoleOutput += "   Error: \(error)\n"
                            }
                        case .skipped:
                            self.consoleOutput += "⏭️ Skipped: \(fileName)\n"
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
            consoleOutput += String(repeating: "=", count: 60) + "\n"
            consoleOutput += "=== BATCH CONVERSION COMPLETED ===\n"
            consoleOutput += summary.description + "\n"
            statusLine = "Batch completed: \(summary.succeeded)/\(summary.total) succeeded"
            
        } catch {
            errorMessage = "Batch conversion error: \(error.localizedDescription)"
            consoleOutput += String(repeating: "=", count: 60) + "\n"
            consoleOutput += "❌ BATCH ERROR: \(error.localizedDescription)\n"
        }
        
        isRunning = false
    }
    
    private func startSingle() async {
        guard !isRunning else { return }
        
        // Store whether we started accessing resources
        var inputStarted = false
        var outputStarted = false
        var inputDirStarted = false
        var outputDirStarted = false
        
        do {
            // Start accessing security-scoped resources for files
            if let inputURL = inputURL {
                inputStarted = inputURL.startAccessingSecurityScopedResource()
                // Also try to get access to parent directory
                let inputDir = inputURL.deletingLastPathComponent()
                inputDirStarted = inputDir.startAccessingSecurityScopedResource()
            }
            if let outputURL = outputURL {
                outputStarted = outputURL.startAccessingSecurityScopedResource()
                // Also try to get access to parent directory
                let outputDir = outputURL.deletingLastPathComponent()
                outputDirStarted = outputDir.startAccessingSecurityScopedResource()
            }
            
            let args = try buildArguments()
            isRunning = true
            progress = 0
            statusLine = "Starting..."
            errorMessage = nil
            
            // Clear and initialize console output
            let cmdLine = "\(chdmanPath) \(args.joined(separator: " "))"
            consoleOutput = "$ \(cmdLine)\n"
            consoleOutput += String(repeating: "=", count: 60) + "\n"

            try await task.run(chdmanPath: chdmanPath, arguments: args) { [weak self] pct, line in
                Task { @MainActor in
                    if pct >= 0 { self?.progress = pct }
                    self?.statusLine = line
                    
                    // Append to console output
                    if !line.isEmpty {
                        self?.consoleOutput += line + "\n"
                    }
                }
            }
            
            statusLine = "Conversion completed successfully!"
            consoleOutput += String(repeating: "=", count: 60) + "\n"
            consoleOutput += "✅ SUCCESS: Conversion completed!\n"
            progress = 1.0
        } catch let error as NSError {
            // Log error to console
            consoleOutput += String(repeating: "=", count: 60) + "\n"
            consoleOutput += "❌ ERROR: \(error.localizedDescription)\n"
            
            // Provide more helpful error messages
            let errorCode = error.code
            let errorDomain = error.domain
            
            if errorDomain == NSCocoaErrorDomain {
                switch errorCode {
                case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                    errorMessage = "Permission denied. Go to Xcode → Target → Signing & Capabilities → Remove 'App Sandbox'."
                case NSFileNoSuchFileError:
                    errorMessage = "File not found. Please verify input file exists."
                case NSFileWriteFileExistsError:
                    errorMessage = "Output file already exists. Enable '-f' option to force overwrite."
                default:
                    errorMessage = "File error: \(error.localizedDescription)"
                }
            } else if errorDomain == "SwiftCHDTask" {
                if errorCode == -1 {
                    errorMessage = error.localizedDescription + "\n\nMake sure the chdman path is correct (should end with /chdman)."
                } else {
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
        if inputStarted, let inputURL = inputURL {
            inputURL.stopAccessingSecurityScopedResource()
        }
        if outputStarted, let outputURL = outputURL {
            outputURL.stopAccessingSecurityScopedResource()
        }
        if inputDirStarted, let inputURL = inputURL {
            inputURL.deletingLastPathComponent().stopAccessingSecurityScopedResource()
        }
        if outputDirStarted, let outputURL = outputURL {
            outputURL.deletingLastPathComponent().stopAccessingSecurityScopedResource()
        }
        
        isRunning = false
    }
}

