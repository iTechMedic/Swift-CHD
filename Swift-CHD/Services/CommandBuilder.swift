import Foundation

/// A fully-formed chdman invocation, plus any files chdman will write that the user did not ask
/// for and should not be left holding.
nonisolated struct ConversionCommand {
    let arguments: [String]
    /// Files chdman produces only because its CLI demands them. Deleted once the run finishes.
    let scratchFiles: [URL]
}

/// Builds chdman argument vectors, so Single and Batch mode cannot drift apart.
nonisolated enum CommandBuilder {

    static func command(
        for conversionType: ConversionType,
        input: URL,
        output: URL,
        options: [SwiftCHDOption]
    ) -> ConversionCommand {
        var args = [conversionType.chdmanCommand]
        var scratch: [URL] = []

        args += ["-i", input.path(percentEncoded: false)]

        if conversionType.writesDataToOutputBin {
            // extractcd always splits its output in two: a TOC/cue sheet to -o, and the actual
            // track data to -ob (defaulting to a sibling .bin). For CHD -> ISO the data *is*
            // what the user asked for, so -ob takes their path and -o gets a throwaway cue.
            //
            // Without this the ".iso" chdman produced was a ~98-byte text file beginning
            // "CD_ROM", and the real disc image landed in a ".bin" next to it.
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

        return ConversionCommand(arguments: args, scratchFiles: scratch)
    }

    /// Removes scratch files left by a completed run, successful or not.
    static func cleanUp(_ command: ConversionCommand) {
        for url in command.scratchFiles {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
