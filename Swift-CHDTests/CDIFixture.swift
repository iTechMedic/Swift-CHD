//  CDIFixture.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation

/// Builds synthetic DiscJuggler images so the parser can be tested without shipping a real disc.
///
/// The layout mirrors what `CDIImage` expects: a run of track data, then a table of records each
/// introduced by a doubled marker, then an 8-byte trailer locating the table.
enum CDIFixture {

    struct TrackSpec {
        var mode: Int           // 0 = audio, 1 = Mode1, 2 = Mode2
        var sectorSizeCode: Int // 0 = 2048, 1 = 2336, 2 = 2352
        var pregap: Int
        var length: Int
        var lba: Int

        static func audio(lba: Int, length: Int, pregap: Int = 0) -> TrackSpec {
            TrackSpec(mode: 0, sectorSizeCode: 2, pregap: pregap, length: length, lba: lba)
        }

        static func mode2(lba: Int, length: Int, pregap: Int = 150) -> TrackSpec {
            TrackSpec(mode: 2, sectorSizeCode: 1, pregap: pregap, length: length, lba: lba)
        }
    }

    static let marker: [UInt8] = [0, 0, 1, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF]
    static let version35: UInt32 = 0x8000_0006

    static func sectorSize(_ code: Int) -> Int {
        switch code {
        case 0: return 2048
        case 1: return 2336
        default: return 2352
        }
    }

    /// Assembles an image whose track table accounts for its data area exactly, as a real one does.
    static func make(sessions: [[TrackSpec]],
                     version: UInt32 = version35,
                     corruptTotalLengthBy: Int = 0) -> Data {
        var data = Data()
        for session in sessions {
            for track in session {
                let bytes = (track.pregap + track.length) * sectorSize(track.sectorSizeCode)
                data.append(Data(repeating: 0xAB, count: bytes))
            }
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

                var body = [UInt8](repeating: 0, count: 120)
                put(&body, 33, Int32(track.pregap))
                put(&body, 37, Int32(track.length))
                put(&body, 47, Int32(track.mode))
                put(&body, 59, Int32(index))
                put(&body, 63, Int32(track.lba))
                put(&body, 67, Int32(track.pregap + track.length + corruptTotalLengthBy))
                put(&body, 87, Int32(track.sectorSizeCode))
                header.append(contentsOf: body)
            }
        }

        appendU32(&header, version)
        appendU32(&header, 0)  // size placeholder, patched once the total is known

        var out = data
        out.append(header)

        // Version 3.5 stores the table's *size*, which `read` resolves as fileSize - size.
        let tableSize = out.count - headerStart
        out.replaceSubrange((out.count - 4)..<out.count, with: leBytes(UInt32(tableSize)))
        return out
    }

    /// Writes `data` to a temporary file and returns its URL. Caller deletes it.
    static func write(_ data: Data, name: String = "fixture.cdi") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdifixture-\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
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
