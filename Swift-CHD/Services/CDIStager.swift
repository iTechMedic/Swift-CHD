//  CDIStager.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation

/// Turns a DiscJuggler image into one raw file per track plus a GDI, which chdman can read.
///
/// GDI is the only sidecar chdman accepts that states a track's absolute LBA. Cue and toc merely
/// concatenate, which drops a Dreamcast disc's session gap and hides the whole filesystem.
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

    /// Big enough that syscall overhead disappears, small enough that cancellation stays prompt.
    private static let chunkBytes = 4 * 1024 * 1024

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
        progress: (Double) -> Void,
        isCancelled: () -> Bool
    ) throws -> Staged {
        try verifyTracksAreConvertible(image)

        let totalBytes = stagedSize(of: image)
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

        var entries: [String] = []
        var bytesWritten: Int64 = 0

        for track in image.tracks {
            let name = fileName(for: track)
            let trackURL = directory.appendingPathComponent(name)

            guard FileManager.default.createFile(atPath: trackURL.path(percentEncoded: false),
                                                 contents: nil) else {
                throw CDIError.corrupt("could not create \(name)")
            }
            guard let writer = try? FileHandle(forWritingTo: trackURL) else {
                throw CDIError.corrupt("could not write \(name)")
            }

            do {
                try write(track: track, from: reader, to: writer) { chunk in
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
            entries.append("\(track.number) \(track.gdiLBA) \(track.isAudio ? 0 : 4) "
                           + "\(rawSectorSize) \(name) 0")
        }

        let gdiURL = directory.appendingPathComponent("disc.gdi")
        let gdi = "\(image.tracks.count)\n" + entries.joined(separator: "\n") + "\n"
        try gdi.write(to: gdiURL, atomically: true, encoding: .utf8)

        succeeded = true
        return Staged(gdiURL: gdiURL, directory: directory)
    }

    /// Bytes staging will write, which is also roughly the free space it needs.
    static func stagedSize(of image: CDIImage) -> Int64 {
        image.tracks.reduce(0) { $0 + Int64($1.length) * Int64(rawSectorSize) }
    }

    // MARK: - Track data

    /// Copies one track's sectors, converting them to raw 2352-byte form on the way.
    /// `onChunk` receives the number of bytes written and may throw to abort.
    private static func write(
        track: CDITrack,
        from reader: FileHandle,
        to writer: FileHandle,
        onChunk: (Int) throws -> Void
    ) throws {
        try reader.seek(toOffset: UInt64(track.byteOffset))

        let sectorsPerChunk = max(1, chunkBytes / track.sectorSize)
        var sectorsRemaining = track.length
        var sectorIndex = 0

        while sectorsRemaining > 0 {
            let count = min(sectorsPerChunk, sectorsRemaining)
            guard let input = try reader.read(upToCount: count * track.sectorSize),
                  input.count == count * track.sectorSize else {
                throw CDIError.corrupt("track \(track.number) is shorter than its table claims")
            }

            let output: Data
            if track.sectorSize == rawSectorSize {
                output = input
            } else {
                output = expand(input, of: track, startingAt: sectorIndex, count: count)
            }
            try writer.write(contentsOf: output)

            sectorsRemaining -= count
            sectorIndex += count
            try onChunk(output.count)
        }
    }

    /// Rebuilds the sector framing DiscJuggler stripped: a 12-byte sync pattern and a 4-byte
    /// header carrying the sector's own address, which is what tells a reader where it belongs.
    private static func expand(_ input: Data, of track: CDITrack,
                               startingAt firstSector: Int, count: Int) -> Data {
        var output = Data(capacity: count * rawSectorSize)
        let bytes = [UInt8](input)

        for i in 0..<count {
            let sectorStart = output.count

            // The stored address is disc-absolute, counted from the lead-in - the same origin
            // DiscJuggler's own `lba` field uses.
            output.append(contentsOf: header(forAbsoluteLBA: track.lba + track.pregap + firstSector + i,
                                             mode: UInt8(track.mode)))

            // A Mode2 sector opens with an 8-byte subheader. At 2336 bytes it is already there;
            // at 2048 only user data survived, so synthesise a Form 1 subheader.
            if track.mode == 2 && track.sectorSize == 2048 {
                output.append(contentsOf: [0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x08, 0x00] as [UInt8])
            }

            let start = i * track.sectorSize
            output.append(contentsOf: bytes[start..<(start + track.sectorSize)])

            // Zero-fill the error-correction area the image never stored. Real EDC/ECC would need
            // Reed-Solomon P/Q, and nothing that reads a CHD - chdman included - verifies it.
            let padding = rawSectorSize - (output.count - sectorStart)
            if padding > 0 { output.append(Data(repeating: 0, count: padding)) }
        }

        return output
    }

    /// Sync pattern, then the sector's address in BCD minutes/seconds/frames and its mode byte.
    ///
    /// `lba` is the *absolute* address, counted from the lead-in, so it is converted to MSF as-is.
    /// Do not add the usual 150-frame offset here: callers pass `track.lba + track.pregap`, and
    /// DiscJuggler's `lba` already includes the lead-in (`CDITrack.gdiLBA` subtracts it back off).
    private static func header(forAbsoluteLBA lba: Int, mode: UInt8) -> [UInt8] {
        var bytes: [UInt8] = [0x00]
        bytes.append(contentsOf: Array(repeating: 0xFF, count: 10))
        bytes.append(0x00)

        let minutes = lba / (60 * 75)
        let seconds = (lba / 75) % 60
        let frames = lba % 75
        bytes.append(contentsOf: [bcd(minutes), bcd(seconds), bcd(frames), mode])

        return bytes
    }

    private static func bcd(_ value: Int) -> UInt8 {
        UInt8(((value / 10) % 10) << 4 | (value % 10))
    }

    // MARK: - Pre-flight

    /// Rejects mode/sector-size combinations we have no conversion for, before writing anything.
    private static func verifyTracksAreConvertible(_ image: CDIImage) throws {
        for track in image.tracks {
            switch (track.mode, track.sectorSize) {
            case (0, rawSectorSize),        // audio, already raw
                 (1, 2048), (1, rawSectorSize),
                 (2, 2048), (2, 2336), (2, rawSectorSize):
                continue
            case (0, let size):
                throw CDIError.unsupportedTrack(
                    "track \(track.number) is audio stored at \(size) bytes per sector, not \(rawSectorSize)")
            case (let mode, let size):
                throw CDIError.unsupportedTrack(
                    "track \(track.number) is mode \(mode) at \(size) bytes per sector")
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

    private static func fileName(for track: CDITrack) -> String {
        // Deliberately plain: chdman's GDI parser splits on whitespace, so naming these after the
        // source image would break on any disc whose title contains a space.
        String(format: "track%02d.%@", track.number, track.isAudio ? "raw" : "bin")
    }
}
