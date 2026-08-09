import Foundation

/// Whether `chdman` can actually perform a conversion, and what to tell the user if it can't.
nonisolated enum CHDManSupport: Equatable {
    case supported
    /// `reason` states the limitation; `guidance` tells the user what to do instead.
    case unsupported(reason: String, guidance: String)

    var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }
}

nonisolated enum ConversionType: String, CaseIterable, Identifiable {
    case isoToChd
    case cueToChd
    case gdiToChd
    case cdiToChd
    case chdToIso
    case chdToCue
    case chdToGdi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isoToChd: return "ISO -> CHD"
        case .cueToChd: return "CUE -> CHD"
        case .gdiToChd: return "GDI -> CHD"
        case .cdiToChd: return "CDI -> CHD"
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
        case .cdiToChd: return "Convert Dreamcast CDI to CHD"
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
        case .cdiToChd: return "cdi"
        case .chdToIso, .chdToCue, .chdToGdi: return "chd"
        }
    }

    var outputExtension: String {
        switch self {
        case .isoToChd, .cueToChd, .gdiToChd, .cdiToChd: return "chd"
        case .chdToIso: return "iso"
        case .chdToCue: return "cue"
        case .chdToGdi: return "gdi"
        }
    }

    var chdmanCommand: String {
        switch self {
        case .isoToChd, .cueToChd, .gdiToChd, .cdiToChd:
            return "createcd"
        case .chdToIso, .chdToCue, .chdToGdi:
            return "extractcd"
        }
    }

    /// True when the file the user asked for is chdman's *data* output (`-ob`) rather than the
    /// TOC/cue sheet it writes to `-o`.
    ///
    /// An ISO is raw track data, so CHD -> ISO wants the data file. CUE and GDI conversions
    /// genuinely want the sheet, with the tracks alongside it. See `CommandBuilder`.
    var writesDataToOutputBin: Bool { self == .chdToIso }

    // Start with minimal defaults - users enable what they need
    var defaultOptions: [SwiftCHDOption] {
        return []  // No options by default, cleaner starting point
    }

    /// Input extensions `chdman`'s `createcd` actually dispatches on. Anything else falls
    /// through to a zero-track TOC, at which point chdman divides by zero and spins forever
    /// printing "Compressing, nan% complete...", leaving a 124-byte stub CHD behind.
    static let chdmanSupportedInputExtensions: Set<String> = ["cue", "gdi", "nrg", "iso", "cdr", "toc"]

    /// Little-endian trailer values identifying a DiscJuggler image, read as a UInt32 at
    /// `EOF - 8`. Matches CDIrip's `CDI_init`, which is the de facto reference for the format.
    static let cdiTrailerVersions: Set<UInt32> = [0x8000_0004, 0x8000_0005, 0x8000_0006]

    /// Whether chdman can perform this conversion at all.
    ///
    /// chdman has never had a DiscJuggler (CDI) parser - the only "CDI" string in the binary is
    /// the `CDI/2352` *track mode* used inside CUE/TOC sheets, which is unrelated to the
    /// container format. MAME closed the request to add one as "not planned" (mamedev/mame#11457).
    var chdmanSupport: CHDManSupport {
        switch self {
        case .cdiToChd:
            return .unsupported(
                reason: "chdman cannot read DiscJuggler (.cdi) images.",
                guidance: """
                This is a limitation of chdman itself, not Swift-CHD - MAME declined to add \
                CDI support upstream, so no version of chdman can convert these files.

                To convert this disc:
                  1. Extract the CDI to GDI or BIN+CUE using CDIrip
                  2. Open the resulting .gdi or .cue file here
                """
            )
        case .isoToChd, .cueToChd, .gdiToChd, .chdToIso, .chdToCue, .chdToGdi:
            return .supported
        }
    }

    // Compression codec descriptions
    static let codecDescriptions: [String: String] = [
        "cdlz,cdzl,cdfl": "chdman's default - picks the best of the three per hunk (recommended)",
        "cdlz": "CD-ROM + LZMA - Smaller size, slower compression, good for archival",
        "cdzl": "CD-ROM + Zlib - Balanced size/speed, good general purpose",
        "cdfl": "CD-ROM + FLAC - Best for audio-heavy games, preserves audio quality",
        "none": "No compression - fastest, but produces the largest CHD"
    ]

    /// Codec choices offered in the UI. `cd` is deliberately absent: chdman rejects it outright
    /// with "Invalid compressor 'cd' specified" and exits 1.
    static let codecChoices = ["cdlz,cdzl,cdfl", "cdlz", "cdzl", "cdfl", "none"]

    // All available options for advanced users.
    //
    // Every entry below is verified against chdman's own usage output. chdman rejects unknown
    // options outright ("Option '-x' not valid for this command") and exits 1, so an option
    // listed here that chdman does not accept turns into a hard conversion failure the moment
    // a user toggles it on. Valid sets are:
    //   createcd:  -o -op -f -i -hs -c -np
    //   extractcd: -o -ob -sb -f -i -ip
    var advancedOptions: [SwiftCHDOption] {
        switch self {
        case .isoToChd, .cueToChd, .gdiToChd, .cdiToChd:
            return [
                SwiftCHDOption(key: "-c", value: "cdlz,cdzl,cdfl", help: "Compression codec", type: .dropdown(Self.codecChoices), isEnabled: false),
                SwiftCHDOption(key: "-hs", value: "", help: "Hunk size in bytes (e.g., 2048, 4096)", type: .text, isEnabled: false),
                SwiftCHDOption(key: "-f", value: "", help: "Force overwrite existing files", type: .flag, isEnabled: false),
                SwiftCHDOption(key: "-np", value: "", help: "Limit CPU cores used (e.g., 4)", type: .text, isEnabled: false)
            ]
        case .chdToIso:
            // No -ob here: CommandBuilder points it at the user's .iso. No -sb either - an ISO
            // is single-track by definition, so per-track files make no sense.
            return [
                SwiftCHDOption(key: "-f", value: "", help: "Force overwrite existing files", type: .flag, isEnabled: false)
            ]
        case .chdToCue, .chdToGdi:
            return [
                SwiftCHDOption(key: "-f", value: "", help: "Force overwrite existing files", type: .flag, isEnabled: false),
                SwiftCHDOption(key: "-sb", value: "", help: "Write one BIN file per track", type: .flag, isEnabled: false),
                SwiftCHDOption(key: "-ob", value: "", help: "Output BIN filename", type: .text, isEnabled: false)
            ]
        }
    }

    // Known options catalog per conversion type, kept in sync with `advancedOptions` above.
    static let knownOptions: [ConversionType: [(String, String?, String, SwiftCHDOptionType)]] = {
        let createCD: [(String, String?, String, SwiftCHDOptionType)] = [
            ("-c", "cdlz,cdzl,cdfl", "Compression codec", .dropdown(codecChoices)),
            ("-hs", "", "Hunk size in bytes", .text),
            ("-f", "", "Force overwrite", .flag),
            ("-np", "", "Limit CPU cores used", .text)
        ]
        let extractCD: [(String, String?, String, SwiftCHDOptionType)] = [
            ("-f", "", "Force overwrite", .flag),
            ("-sb", "", "One BIN file per track", .flag),
            ("-ob", "", "Output BIN filename", .text)
        ]
        return [
            .isoToChd: createCD,
            .cueToChd: createCD,
            .gdiToChd: createCD,
            .cdiToChd: createCD,
            .chdToIso: [("-f", "", "Force overwrite", .flag)],
            .chdToCue: extractCD,
            .chdToGdi: extractCD
        ]
    }()
}
