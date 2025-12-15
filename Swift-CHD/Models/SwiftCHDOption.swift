import Foundation

/// Option type to determine UI representation
enum SwiftCHDOptionType: Hashable {
    case flag      // Simple flag with no value (e.g., -f)
    case text      // Free text input
    case dropdown([String]) // Dropdown with predefined choices
}

struct SwiftCHDOption: Identifiable, Hashable {
    var key: String
    var value: String?
    var help: String
    var type: SwiftCHDOptionType = .text
    var isEnabled: Bool = true

    // Use key as the identifier so SwiftUI can track options consistently
    var id: String { key }

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

    // For Hashable conformance - compare all fields for proper change detection
    static func == (lhs: SwiftCHDOption, rhs: SwiftCHDOption) -> Bool {
        lhs.key == rhs.key &&
        lhs.value == rhs.value &&
        lhs.help == rhs.help &&
        lhs.type == rhs.type &&
        lhs.isEnabled == rhs.isEnabled
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(value)
        hasher.combine(help)
        hasher.combine(type)
        hasher.combine(isEnabled)
    }
}
