//  CDIStager.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation

/// Turns a DiscJuggler image into one raw file per track plus a GDI, which chdman can read.
///
/// # Why this is a rebuild rather than a copy
///
/// A Dreamcast CDI is always a *CD* - a two-session self-boot CD-R, burnt from a GD-ROM so it would
/// play from a plain drive. A CHD of a Dreamcast disc is always a *GD-ROM*: redream and Flycast both
/// hardcode that geometry for CHD input, ignoring the table of contents. redream installs a fixed
/// session table and reads the boot header at address `highDensityLBA` whatever the disc says, and
/// Flycast refuses a CHD with fewer than three tracks outright. So a faithful copy of a CDI, however
/// correct, is a CHD that nothing will boot - which is what earlier versions of Swift-CHD produced.
///
/// What is written here is therefore a GD-ROM built from the CD's contents:
///
/// - every original track keeps the address it had, because the disc's filesystem records absolute
///   addresses and nothing may move out from under them;
/// - a copy of the boot session is added at `highDensityLBA`, giving the emulator the boot header
///   and filesystem descriptor where it insists on finding them;
/// - data tracks are rewritten as Mode 1, the only data track a CHD reader here accepts;
/// - the boot binary is shuffled the way a GD-ROM master holds it, because a self-boot CD stores it
///   straight and the bootstrap that reads a CHD unshuffles whatever it finds.
///
/// # When the boot copy has nowhere to go
///
/// Some discs already have data at `highDensityLBA` - a long first track, or a CDDA track that
/// happens to span it - so the copy cannot be placed without overwriting something. Those fall back
/// to `Strategy.relocate`, which rebuilds the disc around that address: the boot session moves onto
/// it, everything else moves after it, and `ISO9660Relocator` corrects every filesystem address so
/// the files are still found by name.
///
/// Relocating is the second choice, not the first, because it is only sound when the game asks the
/// filesystem where things are. A disc whose boot binary contains its own directory addresses is a
/// game that seeks by raw sector number, would go on reading the addresses it was built with, and
/// is refused rather than converted into a CHD that looks fine and reboot-loops.
///
/// Everything else relocated carries an advisory instead, since only the *boot* binary is checked
/// for embedded addresses.
///
/// # What is refused outright
///
/// A disc carrying CD audio, whichever strategy it would otherwise take - see
/// `verifyDiscHasNoCDAudio`. Its music has nowhere to live on a GD-ROM, and no arrangement of the
/// tracks fixes that.
nonisolated enum CDIStager {

    /// A staged image, ready to hand to chdman.
    struct Staged {
        let gdiURL: URL
        /// Holds the GDI and its track files. Delete when the run finishes.
        let directory: URL
    }

    /// Every track is written as raw 2352-byte sectors: the only sector size GDI allows for a
    /// data track, and the form CHD stores internally anyway.
    static let rawSectorSize = 2352

    /// Where a GD-ROM's high-density area starts, and so where its boot header sits.
    static let highDensityLBA = 45000

    /// Sectors between a track's own start and the address a disc reader counts from.
    private static let leadIn = 150

    /// A GD-ROM's first two tracks share the low-density area; the third opens the high-density
    /// one. Flycast rejects a CHD with fewer, so filler is added if the disc has fewer of its own.
    private static let tracksBeforeHighDensity = 2

    /// Big enough that syscall overhead disappears, small enough that cancellation stays prompt.
    private static let chunkSectors = 2048

    /// A boot binary is loaded whole into a Dreamcast's 16 MB of RAM, so anything beyond that is
    /// not one, and is refused rather than read into memory whole.
    private static let maxBootFileBytes = 16 * 1024 * 1024

    // MARK: - Planning

    /// One track of the GD-ROM being built.
    struct PlannedTrack: Equatable {
        /// Track this is written from, or `nil` for filler the disc does not have.
        let source: CDITrack?
        let number: Int
        /// Absolute address of the track's first sector.
        let lba: Int
        let length: Int
        let isAudio: Bool

        var range: Range<Int> { lba..<(lba + length) }
        var fileName: String {
            String(format: "track%02d.%@", number, isAudio ? "raw" : "bin")
        }
    }

    /// How the disc's contents are made to fit a GD-ROM's shape.
    ///
    /// A self-boot CD does not keep its boot header and its files together: the header sits alone
    /// in a short final session, and the files live in an earlier one. Relocating therefore moves
    /// the two by different amounts - the header to `highDensityLBA`, the files to just after it -
    /// which is why there are two shifts rather than one.
    enum Strategy: Equatable {
        /// Everything stays where it is and the boot session is duplicated at `highDensityLBA`.
        case copyBootSession
        /// Tracks move: the boot session by `boot` sectors, every other track by `data`.
        case relocate(boot: Int, data: Int)

        func shift(forSession session: Int, bootSession: Int) -> Int {
            guard case let .relocate(boot, data) = self else { return 0 }
            return session == bootSession ? boot : data
        }

        var isRelocation: Bool { self != .copyBootSession }
    }

    /// The GD-ROM layout to build, and which addresses hold the binary to be shuffled.
    struct Plan {
        let tracks: [PlannedTrack]
        let strategy: Strategy
        /// Where the boot binary is being written, where it is read from, and its length in bytes.
        let bootFile: (range: Range<Int>, sourceLBA: Int, byteCount: Int)
        /// Replacement user data, keyed by the address it is written to. Empty unless relocating.
        let sectorOverrides: [Int: Data]
        /// Non-nil when the result is worth testing before the CDI is thrown away.
        let advisory: String?
    }

    /// Works out the GD-ROM layout for `image`, or explains why there is not one.
    ///
    /// - Parameter allowingRiskyConversion: Converts discs that would otherwise be refused because
    ///   presenting them as a GD-ROM is known to break the game. The layout is still checked for
    ///   the things that make a CHD structurally impossible; only the judgement calls are waived.
    static func plan(_ image: CDIImage, from source: URL,
                     allowingRiskyConversion: Bool = false) throws -> Plan {
        try verifyTracksAreConvertible(image)

        guard let handle = try? FileHandle(forReadingFrom: source) else {
            throw CDIError.unreadable(source.lastPathComponent)
        }
        defer { try? handle.close() }

        let volume = CDIVolume(image: image, handle: handle)
        let boot = volume.bootTrack
        _ = try volume.bootHeader()

        // After the boot header, so an image that is not a Dreamcast disc at all says that rather
        // than complaining about its music.
        if !allowingRiskyConversion { try verifyDiscHasNoCDAudio(image) }

        let strategy = try strategy(for: image, bootTrack: boot,
                                    allowingRiskyConversion: allowingRiskyConversion)

        // Where the data at any original address ends up. The filesystem's addresses and the
        // tracks are shifted by the same rule, so they cannot drift apart.
        let shift = { (lba: Int) -> Int in
            let session = image.tracks.first { $0.lbaRange.contains(lba) }?.session ?? boot.session
            return strategy.shift(forSession: session, bootSession: boot.session)
        }

        let bootFile = try volume.locateBootFile()
        guard bootFile.byteCount > 0, bootFile.byteCount <= maxBootFileBytes else {
            throw CDIError.notBootable("""
                its boot binary is \(bootFile.byteCount) bytes, which is not a size a Dreamcast \
                could load
                """)
        }
        let bootFileSectors = (bootFile.byteCount + CDIVolume.userDataSize - 1)
            / CDIVolume.userDataSize
        let bootFileStart = bootFile.lba + shift(bootFile.lba)
        let bootFileRange = bootFileStart..<(bootFileStart + bootFileSectors)

        var tracks = try layout(image, bootTrack: boot, strategy: strategy)
        guard tracks.contains(where: { $0.range.overlaps(bootFileRange) }) else {
            throw CDIError.notBootable("""
                its boot binary is recorded at disc address \(bootFile.lba), which none of its \
                tracks covers
                """)
        }

        // Numbering is assigned last so filler and boot copy fall into place by address.
        tracks = tracks.enumerated().map { index, track in
            PlannedTrack(source: track.source, number: index + 1,
                         lba: track.lba, length: track.length, isAudio: track.isAudio)
        }

        // Keyed by destination, so writing only has to look up the address it is already at.
        var overrides: [Int: Data] = [:]
        if strategy.isRelocation {
            if !allowingRiskyConversion {
                let binary = try readBootFile(bootFileRange, sourceLBA: bootFile.lba,
                                              byteCount: bootFile.byteCount, from: volume)
                try verifyRelocationIsSafe(binary, volume: volume)
            }

            overrides = try ISO9660Relocator
                .rewrite(volumeStart: boot.gdiLBA, shift: shift, read: volume.userData(atLBA:))
                .reduce(into: [Int: Data]()) { $0[$1.key + shift($1.key)] = $1.value }
        }

        return Plan(tracks: tracks,
                    strategy: strategy,
                    bootFile: (bootFileRange, bootFile.lba, bootFile.byteCount),
                    sectorOverrides: overrides,
                    advisory: advisory(for: strategy))
    }

    /// Decides whether the boot session can be duplicated where a GD-ROM wants it, or has to move.
    private static func strategy(for image: CDIImage, bootTrack: CDITrack,
                                 allowingRiskyConversion: Bool) throws -> Strategy {
        // The boot copy needs the filesystem descriptor as well as the header, so it runs to the
        // end of the boot track rather than stopping after the header itself.
        let bootCopy = highDensityLBA..<(highDensityLBA + bootTrack.length)
        guard image.tracks.contains(where: { $0.lbaRange.overlaps(bootCopy) }) else {
            return .copyBootSession
        }

        // Something is already there, so nothing can be duplicated into place and the disc has to
        // be rebuilt around the address instead.
        let bootShift = highDensityLBA - bootTrack.gdiLBA
        let bootSession = image.tracks.filter { $0.session == bootTrack.session }
        let bootSessionEnd = bootSession.map { $0.lbaRange.upperBound + bootShift }.max()
            ?? (highDensityLBA + bootTrack.length)

        // Everything else follows the relocated boot session, keeping its own internal spacing.
        let others = image.tracks.filter { $0.session != bootTrack.session }
        let dataShift = others.isEmpty ? 0
            : bootSessionEnd + leadIn - (others.map(\.gdiLBA).min() ?? 0)

        return .relocate(boot: bootShift, data: dataShift)
    }

    /// Places the disc's own tracks, the boot copy, and any filler needed to reach three tracks.
    private static func layout(_ image: CDIImage, bootTrack: CDITrack,
                               strategy: Strategy) throws -> [PlannedTrack] {
        var tracks = image.tracks.map { track in
            let shift = strategy.shift(forSession: track.session, bootSession: bootTrack.session)
            return PlannedTrack(source: track, number: 0, lba: track.gdiLBA + shift,
                                length: track.length, isAudio: track.isAudio)
        }

        // Filler goes between the last low-density track and the high-density area, where a real
        // GD-ROM keeps its second track. It is blank: nothing reads it, it only has to exist.
        //
        // It has to be a *data* track - a reader that finds only audio below the high-density area
        // decides the disc has no regions and refuses it - and, when the disc has nothing of its
        // own down here, the first one has to start at address zero. Addresses are rebased on
        // track 1 when the CHD is written, so a track 1 that starts anywhere else drags every
        // later track down with it and the boot header misses `highDensityLBA` by that much.
        // Clamped rather than counted from `lowDensity.count`: a disc may already have more tracks
        // down here than a GD-ROM does, and needing "minus one" filler is not an error.
        let lowDensity = tracks.filter { $0.lba < highDensityLBA }
        var start = lowDensity.map(\.range.upperBound).max().map { $0 + leadIn } ?? 0
        for _ in 0..<max(0, tracksBeforeHighDensity - lowDensity.count) {
            tracks.append(PlannedTrack(source: nil, number: 0, lba: start,
                                       length: fillerLength, isAudio: false))
            start += fillerLength + leadIn
        }

        if strategy == .copyBootSession {
            tracks.append(PlannedTrack(source: bootTrack, number: 0, lba: highDensityLBA,
                                       length: bootTrack.length, isAudio: bootTrack.isAudio))
        }

        tracks.sort { $0.lba < $1.lba }
        try verify(tracks)
        return tracks
    }

    /// Refuses to relocate a disc whose boot binary reads by address rather than by name.
    ///
    /// Rewriting the filesystem moves every file and keeps it findable by name, but a game that
    /// was built with a table of raw sector numbers never asks the filesystem anything. Such a
    /// disc boots and then reads whatever now happens to sit at the address it remembers.
    ///
    /// The tell is direct: the disc's own directory addresses, sitting in the binary as plain
    /// 32-bit words. Two distinct matches are required before refusing, since one four-byte value
    /// could in principle land by chance - though at roughly one in a million per candidate, it
    /// does not in practice.
    private static func verifyRelocationIsSafe(_ binary: Data, volume: CDIVolume) throws {
        // Small addresses are ordinary integers as often as they are sector numbers.
        let addresses = try volume.rootEntries().filter { $0.lba >= 1000 }
        guard !addresses.isEmpty else { return }

        var wanted: [UInt32: String] = [:]
        for entry in addresses { wanted[UInt32(truncatingIfNeeded: entry.lba)] = entry.name }

        let bytes = [UInt8](binary)
        guard bytes.count >= 4 else { return }
        var found: [String] = []
        var word = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16
        for index in 3..<bytes.count {
            // One pass, sliding a little-endian window a byte at a time.
            word |= UInt32(bytes[index]) << 24
            if let name = wanted[word] {
                found.append(name)
                wanted[word] = nil
                if found.count >= 2 { break }
            }
            word >>= 8
        }

        guard found.count >= 2 else { return }
        throw CDIError.unconvertibleLayout("""
            the disc would have to be rebuilt around disc address \(highDensityLBA), but its boot \
            program reads the disc by raw address - the recorded positions of \
            \(found.joined(separator: " and ")) appear inside it - so moving its files would stop \
            it finding them
            """)
    }

    /// Refuses a disc whose music a GD-ROM has nowhere to put.
    ///
    /// A GD-ROM's boot header sits at `highDensityLBA`, so only that many sectors exist below it;
    /// a CD's soundtrack is usually far larger and has to be placed above, inside the high-density
    /// area. No real Dreamcast plays CD audio from there, and the games tested this way behave
    /// alike: they boot, draw their first screen, and stop - Neo XYX black-screens in redream and
    /// halts on the licence screen in Flycast, while its CDI plays in both.
    ///
    /// This is a property of the disc rather than of the conversion. A build of Neo XYX that moved
    /// nothing at all - every original address kept, the boot header merely copied into place -
    /// failed in exactly the same way, so there is no layout to be cleverer about.
    private static func verifyDiscHasNoCDAudio(_ image: CDIImage) throws {
        let audio = image.tracks.filter(\.isAudio).count
        guard audio > 0 else { return }
        throw CDIError.hasCDAudio(trackCount: audio)
    }

    /// Checks the layout is one a disc could actually have before any of it is written.
    private static func verify(_ tracks: [PlannedTrack]) throws {
        if let first = tracks.first, first.lba < 0 {
            throw CDIError.unconvertibleLayout("""
                laying it out as a GD-ROM would put one of its tracks at disc address \
                \(first.lba), which is before the start of the disc
                """)
        }
        for (previous, next) in zip(tracks, tracks.dropFirst())
        where previous.range.upperBound > next.lba {
            throw CDIError.unconvertibleLayout("""
                laying it out as a GD-ROM would put disc addresses \(next.lba) to \
                \(previous.range.upperBound - 1) in two tracks at once
                """)
        }
        guard tracks.contains(where: { $0.lba == highDensityLBA }) else {
            throw CDIError.unconvertibleLayout(
                "no track of it can be placed at disc address \(highDensityLBA)")
        }
    }

    private static func advisory(for strategy: Strategy) -> String? {
        guard strategy.isRelocation else { return nil }

        return """
            This disc already has data where a GD-ROM keeps its boot header, so Swift-CHD cannot \
            convert it by copying alone. It will rebuild the disc around that address and rewrite \
            the filesystem so every file is still found by name.

            The conversion will work, but the game might not. Some Dreamcast titles read their \
            data by hardcoded sector number rather than by filename, and those addresses are \
            inside the game and cannot be corrected. Such a disc boots and then fails to load.

            Test the CHD before deleting the CDI.
            """
    }

    /// Long enough to be a plausible track, short enough to cost nothing once compressed.
    private static let fillerLength = 300

    /// Reads the boot binary out of the image so its state can be judged before anything is staged.
    private static func readBootFile(_ range: Range<Int>, sourceLBA: Int, byteCount: Int,
                                     from volume: CDIVolume) throws -> Data {
        var data = Data(capacity: byteCount)
        // Read from where the binary is now, not from where it is going.
        for lba in sourceLBA..<(sourceLBA + range.count) {
            guard let sector = try volume.userData(atLBA: lba) else {
                throw CDIError.notBootable("its boot binary is cut short at disc address \(lba)")
            }
            data.append(sector)
        }
        // Re-based, so the offsets used to write it back are the file's own and not the disc's.
        return Data(data.prefix(byteCount))
    }

    // MARK: - Staging

    /// Writes `image`'s tracks and a matching GDI into a fresh temporary directory.
    ///
    /// - Parameters:
    ///   - progress: Fraction of staging completed, 0...1.
    ///   - isCancelled: Polled between chunks; staging stops and cleans up when it returns true.
    /// - Throws: `CDIError`. The temporary directory is removed on any failure.
    static func stage(
        _ image: CDIImage,
        from source: URL,
        allowingRiskyConversion: Bool = false,
        progress: (Double) -> Void,
        isCancelled: () -> Bool
    ) throws -> Staged {
        let plan = try plan(image, from: source,
                            allowingRiskyConversion: allowingRiskyConversion)

        let totalBytes = stagedSize(of: plan)
        try verifyDiskSpace(forBytes: totalBytes)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftchd-cdi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }

        guard let reader = try? FileHandle(forReadingFrom: source) else {
            throw CDIError.unreadable(source.lastPathComponent)
        }
        defer { try? reader.close() }

        let volume = CDIVolume(image: image, handle: reader)
        let bootFile = try bootFileBytes(for: plan, from: volume)

        var entries: [String] = []
        var bytesWritten: Int64 = 0

        for track in plan.tracks {
            let trackURL = directory.appendingPathComponent(track.fileName)
            guard FileManager.default.createFile(atPath: trackURL.path(percentEncoded: false),
                                                 contents: nil) else {
                throw CDIError.corrupt("could not create \(track.fileName)")
            }
            guard let writer = try? FileHandle(forWritingTo: trackURL) else {
                throw CDIError.corrupt("could not write \(track.fileName)")
            }

            do {
                try write(track: track, plan: plan, bootFile: bootFile,
                          from: reader, to: writer) { chunk in
                    if isCancelled() { throw CDIError.cancelled }
                    bytesWritten += Int64(chunk)
                    progress(totalBytes > 0 ? Double(bytesWritten) / Double(totalBytes) : 1)
                }
            } catch {
                try? writer.close()
                throw error
            }
            try? writer.close()

            // trackNumber, LBA, type (0 audio / 4 data), sector size, file, offset into file
            entries.append("\(track.number) \(track.lba) \(track.isAudio ? 0 : 4) "
                           + "\(rawSectorSize) \(track.fileName) 0")
        }

        let gdiURL = directory.appendingPathComponent("disc.gdi")
        let gdi = "\(plan.tracks.count)\n" + entries.joined(separator: "\n") + "\n"
        try gdi.write(to: gdiURL, atomically: true, encoding: .utf8)

        succeeded = true
        return Staged(gdiURL: gdiURL, directory: directory)
    }

    /// Bytes staging will write, which is also roughly the free space it needs.
    static func stagedSize(of plan: Plan) -> Int64 {
        plan.tracks.reduce(0) { $0 + Int64($1.length) * Int64(rawSectorSize) }
    }

    /// The boot binary as it should appear on the staged disc: shuffled, as a GD-ROM master holds it.
    ///
    /// The binary and the bootstrap that loads it are a matched pair. A self-boot CD-R - which a
    /// DiscJuggler image is by construction - stores the binary straight, because the ripper that
    /// made the CD-R unshuffled it. What is being written here is a GD-ROM, and the emulator's
    /// bootstrap unshuffles whatever it finds at that address, so the shuffle has to go back on.
    ///
    /// This is unconditional, and deliberately so. An earlier version guessed at whether a given
    /// binary was already shuffled by looking at its byte statistics; measured against real discs
    /// the guess was wrong often enough to be useless, and getting it wrong loads garbage into RAM
    /// and reboot-loops the game. The format is the reliable signal, not the contents.
    private static func bootFileBytes(for plan: Plan, from volume: CDIVolume) throws -> Data {
        let stored = try readBootFile(plan.bootFile.range, sourceLBA: plan.bootFile.sourceLBA,
                                      byteCount: plan.bootFile.byteCount, from: volume)
        return DreamcastScrambler.scramble(stored)
    }

    // MARK: - Track data

    /// Writes one planned track, converting sectors to the raw form a GD-ROM CHD stores.
    /// `onChunk` receives the number of bytes written and may throw to abort.
    private static func write(
        track: PlannedTrack,
        plan: Plan,
        bootFile: Data,
        from reader: FileHandle,
        to writer: FileHandle,
        onChunk: (Int) throws -> Void
    ) throws {
        guard let source = track.source else {
            try writeFiller(track, to: writer, onChunk: onChunk)
            return
        }

        // The boot copy reads the boot track again from its start, so the offset is measured
        // within the source track rather than from the address being written to.
        try reader.seek(toOffset: UInt64(source.byteOffset))

        var written = 0
        while written < track.length {
            let count = min(chunkSectors, track.length - written)
            guard let input = try reader.read(upToCount: count * source.sectorSize),
                  input.count == count * source.sectorSize else {
                throw CDIError.corrupt("track \(source.number) is shorter than its table claims")
            }

            var output = Data(capacity: count * rawSectorSize)
            for index in 0..<count {
                let lba = track.lba + written + index
                let start = index * source.sectorSize
                let sector = input[input.startIndex.advanced(by: start)...]
                    .prefix(source.sectorSize)
                output.append(try rawSector(from: sector, of: source, at: lba,
                                            plan: plan, bootFile: bootFile))
            }
            try writer.write(contentsOf: output)

            written += count
            try onChunk(output.count)
        }
    }

    /// Rebuilds one sector in the form a GD-ROM CHD holds: 2352 bytes, audio verbatim and data as
    /// Mode 1, which is the only data track redream's and Flycast's CHD readers accept.
    private static func rawSector(from stored: Data.SubSequence, of source: CDITrack, at lba: Int,
                                  plan: Plan, bootFile: Data) throws -> Data {
        if source.isAudio { return Data(stored) }

        guard let dataOffset = source.userDataOffset else {
            throw CDIError.unsupportedTrack(
                "track \(source.number) is mode \(source.mode) at \(source.sectorSize) bytes")
        }
        if source.mode == 2, dataOffset >= 8 {
            // Form 2 trades the error-correction area for 276 more bytes of user data, so its
            // sectors have no 2048-byte area to lift out and no Mode 1 equivalent.
            let subheader = stored[stored.startIndex.advanced(by: dataOffset - 8)]
            if subheader & 0x20 != 0 {
                throw CDIError.unsupportedTrack(
                    "track \(source.number) contains Mode 2 Form 2 sectors")
            }
        }

        var sector = Data(capacity: rawSectorSize)
        sector.append(contentsOf: header(forLBA: lba))

        if let override = plan.sectorOverrides[lba] {
            // A filesystem sector whose addresses no longer describe where its contents ended up.
            sector.append(override)
        } else if plan.bootFile.range.contains(lba) {
            let offset = (lba - plan.bootFile.range.lowerBound) * CDIVolume.userDataSize
            let slice = bootFile[offset..<min(offset + CDIVolume.userDataSize, bootFile.count)]
            sector.append(slice)
            sector.append(Data(repeating: 0, count: CDIVolume.userDataSize - slice.count))
        } else {
            let start = stored.startIndex.advanced(by: dataOffset)
            sector.append(stored[start..<start.advanced(by: CDIVolume.userDataSize)])
        }

        // The error-correction area is left blank. Rebuilding it would need Reed-Solomon P/Q, and
        // nothing that reads a CHD - chdman, redream or Flycast - checks it.
        sector.append(Data(repeating: 0, count: rawSectorSize - sector.count))
        return sector
    }

    private static func writeFiller(_ track: PlannedTrack, to writer: FileHandle,
                                    onChunk: (Int) throws -> Void) throws {
        var written = 0
        while written < track.length {
            let count = min(chunkSectors, track.length - written)
            var block = Data(capacity: count * rawSectorSize)
            for index in 0..<count {
                // Framed like any other data sector, so a reader that checks where it landed
                // gets an answer, with nothing but zeroes inside.
                block.append(contentsOf: header(forLBA: track.lba + written + index))
                block.append(Data(repeating: 0, count: rawSectorSize - 16))
            }
            try writer.write(contentsOf: block)
            written += count
            try onChunk(block.count)
        }
    }

    /// Sync pattern, then the sector's own address in BCD minutes/seconds/frames, then Mode 1.
    ///
    /// The address is what a reader uses to confirm it landed where it meant to, so it has to state
    /// where the sector now sits rather than where it came from - the boot copy is written twice,
    /// to two different addresses, from the same source sectors.
    private static func header(forLBA lba: Int) -> [UInt8] {
        var bytes: [UInt8] = [0x00]
        bytes.append(contentsOf: Array(repeating: 0xFF, count: 10))
        bytes.append(0x00)

        let address = lba + leadIn
        bytes.append(contentsOf: [bcd(address / (60 * 75)), bcd((address / 75) % 60),
                                  bcd(address % 75), 0x01])
        return bytes
    }

    private static func bcd(_ value: Int) -> UInt8 {
        UInt8(((value / 10) % 10) << 4 | (value % 10))
    }

    // MARK: - Pre-flight

    /// Rejects mode/sector-size combinations we have no conversion for, before anything is read.
    private static func verifyTracksAreConvertible(_ image: CDIImage) throws {
        for track in image.tracks {
            if track.isAudio {
                guard track.sectorSize == rawSectorSize else {
                    throw CDIError.unsupportedTrack("track \(track.number) is audio stored at "
                        + "\(track.sectorSize) bytes per sector, not \(rawSectorSize)")
                }
                continue
            }
            guard track.userDataOffset != nil else {
                throw CDIError.unsupportedTrack(
                    "track \(track.number) is mode \(track.mode) at \(track.sectorSize) bytes "
                    + "per sector")
            }
        }
    }

    private static func verifyDiskSpace(forBytes needed: Int64) throws {
        let temp = FileManager.default.temporaryDirectory
        guard let values = try? temp.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return  // Can't tell; let the write fail naturally rather than block on a guess.
        }
        guard available >= needed else {
            throw CDIError.insufficientSpace(needed: needed, available: available)
        }
    }
}
