import Foundation

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
        case .isoToChd: return "ISO -> CHD"
        case .cueToChd: return "CUE -> CHD"
        case .gdiToChd: return "GDI -> CHD"
        case .chdToIso: return "CHD -> ISO"
        case .chdToCue: return "CHD -> CUE"
        case .chdToGdi: return "CHD -> GDI"
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

    // Known options catalog per conversion type (moved from ViewModel)
    static let knownOptions: [ConversionType: [(String, String?, String, SwiftCHDOptionType)]] = [
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
}
