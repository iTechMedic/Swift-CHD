//  CDIFixture.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation
@testable import Swift_CHD

/// Builds synthetic DiscJuggler images so the parser and stager can be tested without shipping a
/// real disc.
///
/// The layout mirrors what `CDIImage` expects: a run of track data, then a table of records each
/// introduced by a doubled marker, then an 8-byte trailer locating the table. `dreamcastDisc` goes
/// further and fills the track data with a boot header and filesystem, which is what `CDIStager`
/// reads before it will convert anything.
enum CDIFixture {

    /// Which of the two record layouts to write. Real images use both - see `CDIImage.Field`.
    enum RecordLayout {
        case short
        case long

        /// Bytes the longer layout inserts ahead of the numeric fields.
        var shift: Int { self == .long ? 8 : 0 }
    }

    struct TrackSpec {
        var mode: Int           // 0 = audio, 1 = Mode1, 2 = Mode2
        var sectorSizeCode: Int // 0 = 2048, 1 = 2336, 2 = 2352
        var pregap: Int
        var length: Int
        var lba: Int
        /// User data to place, keyed by sector index within the track, pregap excluded.
        /// Each value must be exactly `userDataSize` bytes.
        var payload: [Int: Data] = [:]

        static func audio(lba: Int, length: Int, pregap: Int = 0) -> TrackSpec {
            TrackSpec(mode: 0, sectorSizeCode: 2, pregap: pregap, length: length, lba: lba)
        }

        static func mode2(lba: Int, length: Int, pregap: Int = 150,
                          payload: [Int: Data] = [:]) -> TrackSpec {
            TrackSpec(mode: 2, sectorSizeCode: 1, pregap: pregap, length: length, lba: lba,
                      payload: payload)
        }

        static func mode2Raw(lba: Int, length: Int, pregap: Int = 150,
                             payload: [Int: Data] = [:]) -> TrackSpec {
            TrackSpec(mode: 2, sectorSizeCode: 2, pregap: pregap, length: length, lba: lba,
                      payload: payload)
        }
    }

    static let marker: [UInt8] = [0, 0, 1, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF]
    static let version35: UInt32 = 0x8000_0006
    static let version2: UInt32 = 0x8000_0004
    static let userDataSize = 2048

    /// Written at offset 19 past the filename by the builds using the longer record layout.
    static let layoutMarker: UInt32 = 0x8000_0000

    /// Byte a track's unused space is filled with. Deliberately not zero, so a test can tell
    /// payload from padding - but it is kept out of a Mode 2 subheader, where bit 0x20 would
    /// claim the sector is Form 2.
    static let filler: UInt8 = 0xAB

    static func sectorSize(_ code: Int) -> Int {
        switch code {
        case 0: return 2048
        case 1: return 2336
        default: return 2352
        }
    }

    /// Where a sector's user data begins within the bytes an image stores, mirroring `CDITrack`.
    static func userDataOffset(mode: Int, sectorSizeCode: Int) -> Int? {
        switch (mode, sectorSize(sectorSizeCode)) {
        case (1, 2048), (2, 2048): return 0
        case (2, 2336): return 8
        case (1, 2352): return 16
        case (2, 2352): return 24
        default: return nil
        }
    }

    // MARK: - Assembly

    /// Assembles an image whose track table accounts for its data area exactly, as a real one does.
    static func make(sessions: [[TrackSpec]],
                     layout: RecordLayout = .long,
                     version: UInt32 = version35,
                     corruptTotalLengthBy: Int = 0) -> Data {
        var data = Data()
        for session in sessions {
            for track in session { data.append(trackData(track)) }
        }
        let headerStart = data.count

        var header = Data()
        appendU16(&header, UInt16(sessions.count))
        for session in sessions {
            appendU16(&header, UInt16(session.count))
            for (index, track) in session.enumerated() {
                // Four bytes sit between a session's track count and its first record marker;
                // repeating them before every record is harmless and keeps this simple.
                header.append(Data(repeating: 0, count: 4))
                header.append(contentsOf: marker)
                header.append(contentsOf: marker)
                header.append(Data(repeating: 0, count: 4))

                let name = Array("test.cdi".utf8)
                header.append(UInt8(name.count))
                header.append(contentsOf: name)

                var body = [UInt8](repeating: 0, count: 140)
                if layout == .long { put(&body, 19, Int32(bitPattern: layoutMarker)) }
                let shift = layout.shift
                put(&body, shift + 25, Int32(track.pregap))
                put(&body, shift + 29, Int32(track.length))
                put(&body, shift + 39, Int32(track.mode))
                put(&body, shift + 51, Int32(index))
                put(&body, shift + 55, Int32(track.lba))
                put(&body, shift + 59, Int32(track.pregap + track.length + corruptTotalLengthBy))
                put(&body, shift + 79, Int32(track.sectorSizeCode))
                header.append(contentsOf: body)
            }
        }

        appendU32(&header, version)
        appendU32(&header, 0)  // size placeholder, patched once the total is known

        var out = data
        out.append(header)

        // The trailer states the table's *size*, which `read` resolves as fileSize - size.
        let tableSize = out.count - headerStart
        out.replaceSubrange((out.count - 4)..<out.count, with: leBytes(UInt32(tableSize)))
        return out
    }

    /// One track's stored bytes: pregap, then sectors carrying whatever payload was asked for.
    private static func trackData(_ track: TrackSpec) -> Data {
        let size = sectorSize(track.sectorSizeCode)
        let dataOffset = userDataOffset(mode: track.mode, sectorSizeCode: track.sectorSizeCode)

        var data = Data(repeating: filler, count: track.pregap * size)
        for index in 0..<track.length {
            var sector = Data(repeating: filler, count: size)
            if let dataOffset {
                // A Mode 2 subheader must read as Form 1, or the sector has no 2048-byte area.
                if track.mode == 2, dataOffset >= 8 {
                    sector.replaceSubrange((dataOffset - 8)..<dataOffset,
                                           with: Data(repeating: 0, count: 8))
                }
                if let payload = track.payload[index] {
                    precondition(payload.count == userDataSize, "payload must be a full sector")
                    sector.replaceSubrange(dataOffset..<(dataOffset + userDataSize), with: payload)
                }
            }
            data.append(sector)
        }
        return data
    }

    /// Writes `data` to a temporary file and returns its URL. Caller deletes it.
    static func write(_ data: Data, name: String = "fixture.cdi") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdifixture-\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }

    // MARK: - A Dreamcast disc

    /// The shape of a self-boot Dreamcast CD-R, which is what `CDIStager` converts.
    struct DreamcastDisc {
        var sessions: [[TrackSpec]]
        /// The boot binary as it sits in the image, before any shuffling.
        var bootBinary: Data
        /// Where that binary starts, as an absolute disc address.
        var bootFileLBA: Int
        var bootFileSectors: Int
    }

    static let rootDirectoryLBA = 23
    static let defaultBootFileLBA = 40
    static let bootFileName = "1ST_READ.BIN"

    /// Builds a two-session disc: the filesystem and files in session 1, the boot header in
    /// session 2 - the arrangement a self-boot CD-R uses, and the one Namco Museum has.
    ///
    /// - Parameters:
    ///   - bootSessionLBA: Where session 2 begins, or `nil` for a single-session disc whose one
    ///     track opens with the boot header.
    ///   - dataTrackLength: Sectors in session 1, which must hold the filesystem and the binary.
    ///   - bootFileSectors: Length of the binary, in sectors.
    ///   - scrambleBootBinary: Stores the binary already shuffled, as a pressed GD-ROM would.
    ///   - extraTracks: Further session 1 tracks, appended after the data track.
    ///   - addressOffset: Moves the filesystem and the binary further into the data track, so a
    ///     test can give them addresses large enough for `CDIStager` to treat as sector numbers.
    ///   - embedOwnAddresses: Writes the filesystem's own addresses into the boot binary, the way
    ///     a game that seeks by raw address rather than by filename does.
    static func dreamcastDisc(bootSessionLBA: Int? = 14_296,
                              dataTrackLength: Int = 200,
                              bootFileSectors: Int = 8,
                              scrambleBootBinary: Bool = false,
                              extraTracks: [TrackSpec] = [],
                              addressOffset: Int = 0,
                              embedOwnAddresses: Bool = false) -> DreamcastDisc {
        let rootLBA = rootDirectoryLBA + addressOffset
        let bootLBA = defaultBootFileLBA + addressOffset

        var binary = bootBinary(sectors: bootFileSectors)
        if embedOwnAddresses {
            for (index, address) in [rootLBA, bootLBA].enumerated() {
                let raw = UInt32(address)
                let at = 64 + index * 8
                binary.replaceSubrange(at..<(at + 4), with: [UInt8(raw & 0xFF),
                                                            UInt8((raw >> 8) & 0xFF),
                                                            UInt8((raw >> 16) & 0xFF),
                                                            UInt8((raw >> 24) & 0xFF)])
            }
        }
        let stored = scrambleBootBinary ? DreamcastScrambler.scramble(binary) : binary

        var payload: [Int: Data] = [
            16: volumeDescriptor(rootLBA: rootLBA),
            rootLBA: rootDirectory(bootFileLBA: bootLBA, byteCount: stored.count)
        ]
        for sector in 0..<bootFileSectors {
            let start = sector * userDataSize
            payload[bootLBA + sector] = stored[start..<(start + userDataSize)]
        }
        // With no second session, the one track has to carry the boot header itself.
        if bootSessionLBA == nil { payload[0] = bootHeader() }

        let dataTrack = TrackSpec.mode2Raw(lba: 0, length: dataTrackLength, payload: payload)
        let disc = { (sessions: [[TrackSpec]]) in
            DreamcastDisc(sessions: sessions, bootBinary: binary,
                          bootFileLBA: bootLBA, bootFileSectors: bootFileSectors)
        }
        guard let bootSessionLBA else { return disc([[dataTrack] + extraTracks]) }

        // The boot session repeats the descriptor, which is where a reader looks for it.
        let bootTrack = TrackSpec.mode2Raw(lba: bootSessionLBA, length: 32,
                                           payload: [0: bootHeader(),
                                                     16: volumeDescriptor(rootLBA: rootLBA)])
        return disc([[dataTrack] + extraTracks, [bootTrack]])
    }

    /// IP.BIN: the signature a disc is recognised by, and the name of the binary to run.
    static func bootHeader() -> Data {
        var sector = Data(repeating: 0x20, count: userDataSize)
        sector.replaceSubrange(0..<16, with: Array("SEGA SEGAKATANA ".utf8))
        sector.replaceSubrange(16..<32, with: Array("SEGA ENTERPRISES".utf8))
        let name = Array(bootFileName.utf8)
        sector.replaceSubrange(0x60..<(0x60 + name.count), with: name)
        return sector
    }

    /// An ISO 9660 primary volume descriptor pointing at the root directory.
    static func volumeDescriptor(rootLBA: Int = rootDirectoryLBA) -> Data {
        var sector = Data(repeating: 0, count: userDataSize)
        sector[0] = 1
        sector.replaceSubrange(1..<6, with: Array("CD001".utf8))
        sector[6] = 1
        // The root's own directory record is embedded at a fixed offset.
        var record = [UInt8](repeating: 0, count: 34)
        record[0] = 34
        put(&record, 2, Int32(rootLBA))
        put(&record, 10, Int32(userDataSize))
        record[25] = 0x02  // directory
        record[32] = 1
        sector.replaceSubrange(156..<190, with: record)
        return sector
    }

    /// A root directory holding ".", ".." and the boot binary.
    static func rootDirectory(bootFileLBA: Int, byteCount: Int) -> Data {
        var sector = Data(repeating: 0, count: userDataSize)
        var offset = 0

        func append(name: [UInt8], lba: Int, size: Int, isDirectory: Bool) {
            var record = [UInt8](repeating: 0, count: 33 + name.count)
            if record.count % 2 != 0 { record.append(0) }  // records are even-length
            record[0] = UInt8(record.count)
            put(&record, 2, Int32(lba))
            put(&record, 10, Int32(size))
            record[25] = isDirectory ? 0x02 : 0
            record[32] = UInt8(name.count)
            record.replaceSubrange(33..<(33 + name.count), with: name)
            sector.replaceSubrange(offset..<(offset + record.count), with: record)
            offset += record.count
        }

        append(name: [0x00], lba: rootDirectoryLBA, size: userDataSize, isDirectory: true)
        append(name: [0x01], lba: rootDirectoryLBA, size: userDataSize, isDirectory: true)
        append(name: Array("\(bootFileName);1".utf8), lba: bootFileLBA, size: byteCount,
               isDirectory: false)
        return sector
    }

    /// Stand-in for a compiled binary: a block of varied bytes, then zeroes.
    static func bootBinary(sectors: Int) -> Data {
        let total = sectors * userDataSize
        let code = total * 2 / 5
        var data = Data(capacity: total)
        for byte in 0..<code { data.append(UInt8((byte &* 31 &+ byte / 7) & 0xFF)) }
        data.append(Data(repeating: 0, count: total - code))
        return data
    }

    // MARK: - Little-endian helpers

    private static func leBytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    private static func appendU16(_ data: inout Data, _ value: UInt16) {
        data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func appendU32(_ data: inout Data, _ value: UInt32) {
        data.append(contentsOf: leBytes(value))
    }

    private static func put(_ bytes: inout [UInt8], _ offset: Int, _ value: Int32) {
        let raw = UInt32(bitPattern: value)
        for i in 0..<4 { bytes[offset + i] = UInt8((raw >> (8 * UInt32(i))) & 0xFF) }
    }
}
