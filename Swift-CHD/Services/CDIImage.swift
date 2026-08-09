//  CDIImage.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.
//
//  Reader for DiscJuggler (.cdi) images, a format with no published specification.
//
//  The layout encoded here was derived by analysing disc images directly: track records are
//  found by the marker they all begin with, and every field offset below was established by
//  requiring that the resulting track table account for the file byte for byte. That same
//  requirement is enforced at parse time - see `read` - so a wrong offset cannot pass silently.

import Foundation

/// One track described by a DiscJuggler image's track table.
nonisolated struct CDITrack: Equatable {
    /// 1-based session this track belongs to.
    let session: Int
    /// 1-based track number, counted across the whole disc.
    let number: Int
    /// 0 = audio, 1 = Mode1, 2 = Mode2. Matches the value stored in the image.
    let mode: Int
    /// Bytes per sector as stored: 2048, 2336 or 2352.
    let sectorSize: Int
    /// Absolute disc address of the track's pregap, in sectors, including the 150-sector lead-in.
    let lba: Int
    /// Pregap length in sectors. DiscJuggler stores the pregap in the file, ahead of the track.
    let pregap: Int
    /// Track length in sectors, excluding the pregap.
    let length: Int
    /// Pregap + track length, i.e. how much of the file this track occupies.
    let totalLength: Int
    /// Byte offset of the track's first *data* sector - past the pregap.
    let byteOffset: Int

    var pregapByteOffset: Int { byteOffset - pregap * sectorSize }

    /// Where this track starts the way a GDI addresses it. DiscJuggler counts from the lead-in,
    /// GDI from track 1's user data 150 sectors later, and the pregap shifts it further.
    var gdiLBA: Int { lba + pregap - 150 }

    var isAudio: Bool { mode == 0 }
}

/// A parsed DiscJuggler (`.cdi`) image. chdman has no CDI reader and never will
/// (mamedev/mame#11457), so Swift-CHD parses the format itself and stages it out for chdman.
nonisolated struct CDIImage {
    let version: UInt32
    let fileSize: Int
    let sessionCount: Int
    let tracks: [CDITrack]

    // MARK: - Layout

    /// Marks the start of a track record. Written twice, back to back.
    private static let recordMarker: [UInt8] = [0, 0, 1, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF]

    /// Byte offsets of each field, measured from the end of the filename embedded in a record.
    /// Anchoring here rather than at the record start keeps the offsets valid whatever the
    /// authoring machine's path length happened to be.
    private enum Field {
        static let pregap = 33
        static let length = 37
        static let mode = 47
        static let lba = 63
        static let totalLength = 67
        static let sectorSizeCode = 87
        /// Bytes that must be readable past the filename for the fields above to be present.
        static let required = sectorSizeCode + 4
    }

    /// Bytes between a session's track-count word and the first record marker of that session.
    private static let trackCountLead = 6

    /// Largest track table to read into memory. Real ones are a few KB; the bound stops a corrupt
    /// trailer from turning into a multi-gigabyte allocation.
    private static let maxHeaderBytes = 16 * 1024 * 1024

    private static func sectorSize(forCode code: Int) -> Int? {
        switch code {
        case 0: return 2048
        case 1: return 2336
        case 2: return 2352
        default: return nil
        }
    }

    // MARK: - Reading

    static func read(at url: URL) throws -> CDIImage {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw CDIError.unreadable(url.lastPathComponent)
        }
        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd(), end > 8 else { throw CDIError.notDiscJuggler }
        let fileSize = Int(end)

        // CDI carries no magic number at the front. The last eight bytes hold a version word and
        // a second word locating the track table - as a size in some versions, an absolute offset
        // in others. Rather than map versions to meanings, try both and keep whichever parses.
        try handle.seek(toOffset: end - 8)
        guard let trailer = try handle.read(upToCount: 8), trailer.count == 8 else {
            throw CDIError.notDiscJuggler
        }
        let bytes = [UInt8](trailer)
        let version = readU32(bytes, 0)
        let word = Int(readU32(bytes, 4))

        var lastFailure: CDIError = .notDiscJuggler
        for headerStart in [fileSize - word, word] {
            guard headerStart > 0, headerStart < fileSize,
                  fileSize - headerStart <= maxHeaderBytes else { continue }

            try handle.seek(toOffset: UInt64(headerStart))
            guard let data = try handle.read(upToCount: fileSize - headerStart),
                  data.count == fileSize - headerStart else { continue }

            do {
                let (sessions, tracks) = try parseTable([UInt8](data), headerStart: headerStart)
                return CDIImage(version: version, fileSize: fileSize,
                                sessionCount: sessions, tracks: tracks)
            } catch let error as CDIError {
                lastFailure = error
            }
        }

        throw lastFailure
    }

    /// Reads the track table, stopping at the point where the tracks exactly account for the file.
    ///
    /// That endpoint is what makes the parse self-checking: track data occupies every byte from 0
    /// up to the table, so the running total can only land on `headerStart` if every record was
    /// read correctly. It also settles where the table ends - the marker appears again in trailing
    /// structures that are not tracks, and a scan alone would happily read them as garbage.
    private static func parseTable(_ header: [UInt8], headerStart: Int) throws -> (Int, [CDITrack]) {
        // The trailer is two arbitrary words from an untrusted file, so it can point almost
        // anywhere - including one byte from the end. Throwing lets `read` try the other
        // candidate offset instead of indexing off the end of the buffer.
        guard header.count >= 2 else { throw CDIError.corrupt("track table is truncated") }

        let sessionCount = Int(readU16(header, 0))
        guard sessionCount > 0, sessionCount <= 99 else {
            throw CDIError.corrupt("\(sessionCount) sessions")
        }

        var tracks: [CDITrack] = []
        var consumed = 0          // bytes of track data accounted for so far
        var session = 0
        var remainingInSession = 0

        for start in recordStarts(in: header) {
            guard consumed < headerStart else { break }

            // A session's track count sits just ahead of its first record. Counting down from it
            // is what assigns tracks to sessions - the gap chdman must reproduce depends on it.
            if remainingInSession == 0 {
                guard start >= trackCountLead else { throw CDIError.corrupt("misplaced first record") }
                remainingInSession = Int(readU16(header, start - trackCountLead))
                session += 1
                guard remainingInSession > 0, session <= sessionCount else {
                    throw CDIError.corrupt("session \(session) declares \(remainingInSession) tracks")
                }
            }

            let track = try readRecord(header, markerAt: start,
                                       session: session, number: tracks.count + 1,
                                       dataOffset: consumed)
            tracks.append(track)
            consumed += track.totalLength * track.sectorSize
            remainingInSession -= 1
        }

        guard !tracks.isEmpty else { throw CDIError.corrupt("no tracks") }
        guard consumed == headerStart else {
            throw CDIError.corrupt("""
                the track table accounts for \(consumed) bytes but the tracks occupy \(headerStart).

                This image uses a DiscJuggler layout Swift-CHD does not recognise.
                """)
        }

        return (session, tracks)
    }

    /// Offsets of every doubled record marker, in order.
    private static func recordStarts(in header: [UInt8]) -> [Int] {
        let marker = recordMarker
        let span = marker.count * 2
        guard header.count >= span else { return [] }

        var found: [Int] = []
        for i in 0...(header.count - span) where header[i] == marker[0] {
            if Array(header[i..<(i + marker.count)]) == marker,
               Array(header[(i + marker.count)..<(i + span)]) == marker {
                found.append(i)
            }
        }
        return found
    }

    /// Reads one track record. The embedded filename is variable-length, so the numeric fields
    /// are located relative to its end rather than to the record start.
    private static func readRecord(_ header: [UInt8], markerAt start: Int,
                                   session: Int, number: Int,
                                   dataOffset: Int) throws -> CDITrack {
        let afterMarker = start + recordMarker.count * 2
        let filenameLengthAt = afterMarker + 4
        guard filenameLengthAt < header.count else {
            throw CDIError.corrupt("track \(number) record is truncated")
        }

        let base = filenameLengthAt + 1 + Int(header[filenameLengthAt])
        guard base + Field.required <= header.count else {
            throw CDIError.corrupt("track \(number) record is truncated")
        }

        let pregap = Int(readI32(header, base + Field.pregap))
        let length = Int(readI32(header, base + Field.length))
        let mode = Int(readU32(header, base + Field.mode))
        let lba = Int(readU32(header, base + Field.lba))
        let totalLength = Int(readU32(header, base + Field.totalLength))
        let code = Int(readU32(header, base + Field.sectorSizeCode))

        guard let sectorSize = sectorSize(forCode: code) else {
            throw CDIError.unsupportedTrack("track \(number) has sector size code \(code)")
        }
        guard (0...2).contains(mode) else {
            throw CDIError.unsupportedTrack("track \(number) has mode \(mode)")
        }
        guard pregap >= 0, length > 0, totalLength >= pregap + length else {
            throw CDIError.corrupt(
                "track \(number) has pregap \(pregap), length \(length), total \(totalLength)")
        }

        return CDITrack(session: session, number: number, mode: mode, sectorSize: sectorSize,
                        lba: lba, pregap: pregap, length: length, totalLength: totalLength,
                        byteOffset: dataOffset + pregap * sectorSize)
    }

    // MARK: - Little-endian reads

    private static func readU16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func readU32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    private static func readI32(_ b: [UInt8], _ i: Int) -> Int32 {
        Int32(bitPattern: readU32(b, i))
    }

    // MARK: - Detection

    /// Whether `url` is a DiscJuggler image, judged by whether it actually parses as one.
    ///
    /// Content rather than extension: chdman accepts a CDI named `.iso` as a single
    /// 2048-byte-sector track and compresses it into an unusable CHD.
    static func looksLikeDiscJuggler(at url: URL) -> Bool {
        (try? read(at: url)) != nil
    }
}

// MARK: - Errors

nonisolated enum CDIError: LocalizedError, Equatable {
    case unreadable(String)
    case notDiscJuggler
    case corrupt(String)
    case unsupportedTrack(String)
    case insufficientSpace(needed: Int64, available: Int64)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "Could not open \"\(name)\" for reading."
        case .notDiscJuggler:
            return "This file is not a DiscJuggler image, or uses a variant Swift-CHD cannot read."
        case .corrupt(let detail):
            return "This DiscJuggler image could not be read: \(detail)"
        case .unsupportedTrack(let detail):
            return "This DiscJuggler image contains a track Swift-CHD cannot convert: \(detail)"
        case .insufficientSpace(let needed, let available):
            let neededText = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            let availableText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return """
                Not enough free disk space to convert this image.

                Converting a CDI needs about \(neededText) of temporary space; \
                \(availableText) is free.
                """
        case .cancelled:
            return "Conversion cancelled."
        }
    }
}
