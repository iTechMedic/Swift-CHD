//  CommandBuilder.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation

/// A fully-formed chdman invocation, plus any files chdman will write that the user did not ask
/// for and should not be left holding.
nonisolated struct ConversionCommand {
    let arguments: [String]
    /// Files and directories produced only to satisfy chdman's CLI, or to give it an input it
    /// can read. Deleted once the run finishes.
    let scratchFiles: [URL]
    /// How much of the job was already done before chdman started, 0...1. Non-zero when the
    /// input had to be staged first, so the bar does not rewind to zero when chdman takes over.
    let progressFloor: Double

    init(arguments: [String], scratchFiles: [URL], progressFloor: Double = 0) {
        self.arguments = arguments
        self.scratchFiles = scratchFiles
        self.progressFloor = progressFloor
    }

    /// Rescales a chdman percentage into overall job progress.
    func overallProgress(_ chdmanProgress: Double) -> Double {
        progressFloor + chdmanProgress * (1 - progressFloor)
    }
}

/// Builds chdman argument vectors, so Single and Batch mode cannot drift apart.
nonisolated enum CommandBuilder {

    /// The input chdman will actually be pointed at, which is not always the file the user chose.
    struct PreparedInput: Sendable {
        let url: URL
        /// Anything created to produce `url`, for `cleanUp` to remove afterwards.
        let scratch: [URL]
        /// Share of the overall job that preparing this input represented.
        let progressFloor: Double

        /// An input chdman can already read, used as-is.
        static func asIs(_ url: URL) -> PreparedInput {
            PreparedInput(url: url, scratch: [], progressFloor: 0)
        }
    }

    /// Fraction of a CDI conversion's progress bar given over to staging. Staging writes the
    /// whole disc out, but chdman then reads it all back and compresses it, which takes longer.
    static let cdiStagingProgressShare = 0.15

    /// Whether `inputURL` has to be rewritten before chdman can read it. Decided by content, not
    /// extension, so a DiscJuggler image named `.iso` converts instead of being quietly mangled.
    static func requiresStaging(_ inputURL: URL, conversionType: ConversionType) -> Bool {
        guard conversionType.chdmanCommand == "createcd" else { return false }
        return InputValidator.isDiscJugglerImage(at: inputURL)
    }

    static func command(
        for conversionType: ConversionType,
        input: PreparedInput,
        output: URL,
        options: [SwiftCHDOption]
    ) -> ConversionCommand {
        var args = [conversionType.chdmanCommand]
        var scratch: [URL] = input.scratch

        args += ["-i", input.url.path(percentEncoded: false)]

        if conversionType.writesDataToOutputBin {
            // extractcd splits its output: a cue sheet to -o and track data to -ob. For CHD ->
            // ISO the data is what was asked for, so -ob takes their path and -o a throwaway cue.
            let toc = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftchd-toc-\(UUID().uuidString).cue")
            args += ["-o", toc.path(percentEncoded: false)]
            args += ["-ob", output.path(percentEncoded: false)]
            scratch.append(toc)
        } else {
            args += ["-o", output.path(percentEncoded: false)]
        }

        for opt in options where opt.isEnabled {
            let key = opt.key.lowercased()
            // -i and -o are ours; so is -ob whenever we are redirecting the data file.
            if key == "-i" || key == "-o" { continue }
            if key == "-ob" && conversionType.writesDataToOutputBin { continue }
            args += opt.asArguments
        }

        return ConversionCommand(arguments: args,
                                 scratchFiles: scratch,
                                 progressFloor: input.progressFloor)
    }

    /// Removes scratch left by a completed run, successful or not.
    static func cleanUp(_ command: ConversionCommand) {
        for url in command.scratchFiles {
            // Staged CDI tracks live in a directory; removeItem takes both.
            try? FileManager.default.removeItem(at: url)
        }
    }
}
