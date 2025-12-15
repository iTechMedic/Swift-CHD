import Foundation

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
