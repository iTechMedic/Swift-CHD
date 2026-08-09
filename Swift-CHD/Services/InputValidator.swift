import Foundation

/// Pre-flight validation of conversion inputs, performed before chdman is launched.
///
/// chdman is unforgiving about input it cannot parse. Rather than reporting an error, its
/// `createcd` command falls through to a zero-track TOC, divides by zero computing progress,
/// and then loops forever printing "Compressing, nan% complete...", leaving a 124-byte stub
/// CHD behind. Rejecting bad input here turns that hang into an actionable message.
nonisolated enum InputValidator {

    /// Checks whether chdman can actually read `inputURL` for the given conversion.
    ///
    /// - Returns: `nil` when the input is usable, otherwise a user-facing explanation.
    static func rejectionReason(for inputURL: URL, conversionType: ConversionType) -> String? {
        // 1. Conversions chdman cannot perform at all, whatever the file contains.
        if case let .unsupported(reason, guidance) = conversionType.chdmanSupport {
            return "\(reason)\n\n\(guidance)"
        }

        // Extraction reads a CHD, which chdman validates itself and reports properly.
        guard conversionType.chdmanCommand == "createcd" else { return nil }

        let ext = inputURL.pathExtension.lowercased()

        // 2. A DiscJuggler image wearing a supported extension. This one is worth catching
        //    precisely because chdman does *not* hang on it: a CDI named .iso is accepted as a
        //    single 2048-byte-sector track and silently compressed into a garbage CHD.
        if isDiscJugglerImage(at: inputURL) {
            guard case let .unsupported(reason, guidance) = ConversionType.cdiToChd.chdmanSupport else {
                return nil
            }
            return """
                "\(inputURL.lastPathComponent)" is a DiscJuggler image, despite its .\(ext) extension.

                \(reason)

                \(guidance)
                """
        }

        // 3. Any other extension chdman does not dispatch on.
        guard ConversionType.chdmanSupportedInputExtensions.contains(ext) else {
            let supported = ConversionType.chdmanSupportedInputExtensions
                .sorted()
                .map { ".\($0)" }
                .joined(separator: ", ")
            return """
                chdman cannot read .\(ext) files.

                Supported CD image formats are: \(supported)
                """
        }

        return nil
    }

    /// Detects a DiscJuggler image from its trailer.
    ///
    /// CDI stores no leading magic number; the format is identified by a little-endian UInt32
    /// version at `EOF - 8`, followed by a header offset. This mirrors CDIrip's `CDI_init`,
    /// which is the de facto reference implementation for the format.
    static func isDiscJugglerImage(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size >= 8 else { return false }
        guard (try? handle.seek(toOffset: size - 8)) != nil else { return false }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }

        let bytes = [UInt8](data)
        let version = UInt32(bytes[0])
            | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24

        return ConversionType.cdiTrailerVersions.contains(version)
    }
}
