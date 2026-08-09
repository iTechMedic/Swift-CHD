//  InputValidator.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation

/// Pre-flight validation of conversion inputs, performed before chdman is launched. Input chdman
/// cannot parse makes it spin forever on "nan% complete" rather than fail, so reject it here.
nonisolated enum InputValidator {

    /// Checks whether `inputURL` is usable for the given conversion.
    /// - Returns: `nil` when it is, otherwise a user-facing explanation.
    static func rejectionReason(for inputURL: URL, conversionType: ConversionType) -> String? {
        // 1. Conversions chdman cannot perform at all, whatever the file contains.
        if case let .unsupported(reason, guidance) = conversionType.chdmanSupport {
            return "\(reason)\n\n\(guidance)"
        }

        // Extraction reads a CHD, which chdman validates itself and reports properly.
        guard conversionType.chdmanCommand == "createcd" else { return nil }

        let ext = inputURL.pathExtension.lowercased()

        // 2. A DiscJuggler image, whatever it is called - Swift-CHD reads these itself, so the
        //    only question is whether this one parses. Catching it here also stops a CDI misnamed
        //    .iso being accepted by chdman as one 2048-byte-sector track and compressed to junk.
        do {
            _ = try CDIImage.read(at: inputURL)
            return nil
        } catch CDIError.notDiscJuggler, CDIError.unreadable(_) {
            // No DiscJuggler structure at all, so it is simply some other format - or one we
            // cannot open, which chdman will report better than we can. Fall through.
        } catch {
            // The trailer pointed somewhere plausible but the track table did not hold up.
            return """
                "\(inputURL.lastPathComponent)" could not be read as a DiscJuggler image.

                \((error as? CDIError)?.errorDescription ?? error.localizedDescription)
                """
        }

        // 3. A file claiming to be a CDI that has no DiscJuggler structure at all. Caught
        //    separately because .cdi is not an extension chdman can fall back on.
        if ext == "cdi" {
            return """
                "\(inputURL.lastPathComponent)" does not appear to be a DiscJuggler image, \
                despite its .cdi extension.

                No DiscJuggler trailer and track table could be read from it. The file may be \
                truncated, corrupt, or a different format that was renamed.
                """
        }

        // 4. Any other extension nothing here dispatches on. .cdi is listed as readable but
        //    cannot reach this point - it already failed the DiscJuggler check above.
        guard ConversionType.chdmanSupportedInputExtensions.contains(ext) else {
            let supported = ConversionType.chdmanSupportedInputExtensions.union(["cdi"])
                .sorted()
                .map { ".\($0)" }
                .joined(separator: ", ")
            return """
                Swift-CHD cannot read .\(ext) files.

                Supported CD image formats are: \(supported)
                """
        }

        return nil
    }

    /// Detects a DiscJuggler image by whether its track table actually parses, rather than by a
    /// version number - a file that identifies as CDI but cannot be read is no use to us anyway.
    static func isDiscJugglerImage(at url: URL) -> Bool {
        CDIImage.looksLikeDiscJuggler(at: url)
    }
}
