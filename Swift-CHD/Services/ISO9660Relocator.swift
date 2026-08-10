//  ISO9660Relocator.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation

/// Rewrites the addresses in an ISO 9660 filesystem so its contents can be moved bodily to a new
/// place on the disc.
///
/// `CDIStager` prefers never to move anything, because a Dreamcast disc records absolute addresses
/// and moving data invalidates them. When the boot session cannot stay where it is - the emulator
/// insists on a boot track at `CDIStager.highDensityLBA` and the disc already has data there - the
/// only remaining option is to shift the session and correct every address that pointed into it.
///
/// The addresses live in three places, and all three have to agree:
///
/// - the volume descriptors, which hold the path table locations and the root directory record;
/// - the path tables themselves, one little-endian and one big-endian, plus optional copies;
/// - the extent field of every directory record, in every directory, recursively.
///
/// # What this cannot fix
///
/// Only the *filesystem's* addresses are corrected. A game that ships a build-time table of raw
/// sector numbers and seeks to them directly - which many Dreamcast titles do - will still look in
/// the old places, and no amount of filesystem rewriting can find those tables. Relocation is
/// therefore offered with a warning rather than silently, and a relocated disc has to be tested.
nonisolated enum ISO9660Relocator {

    /// Sector of a volume at which the descriptors begin.
    private static let descriptorSector = 16

    /// Descriptors are terminated by a type-255 record; the bound only stops a corrupt disc from
    /// being followed forever.
    private static let maxDescriptors = 32

    /// Sectors this will rewrite before deciding the filesystem is not one. A real disc's
    /// directory tree is a few hundred sectors; the bound caps memory at 128 MB.
    private static let maxPatchedSectors = 65_536

    private static let identifier = Array("CD001".utf8)

    /// Produces replacement user data for every sector holding an address that a move invalidates.
    ///
    /// The shift is asked for per address rather than given once, because a self-boot disc is not
    /// moved as one piece: its boot session goes to the start of the high-density area while the
    /// session holding the files goes after it, so a descriptor and the directory it points at can
    /// move by different amounts.
    ///
    /// - Parameters:
    ///   - volumeStart: Absolute address the filesystem's own sector numbering counts from, i.e.
    ///     the start of the track carrying its descriptors.
    ///   - shift: Sectors the data at a given original address is moving by.
    ///   - read: Supplies the 2048 bytes of user data at an absolute address, or `nil` if unmapped.
    /// - Returns: Patched sectors keyed by their *original* address.
    static func rewrite(volumeStart: Int, shift: (Int) -> Int,
                        read: (Int) throws -> Data?) throws -> [Int: Data] {
        var patched: [Int: [UInt8]] = [:]

        // Reads through the patches, so a sector visited twice is never shifted twice.
        func sector(_ lba: Int) throws -> [UInt8] {
            if let already = patched[lba] { return already }
            guard let data = try read(lba), data.count == CDIVolume.userDataSize else {
                throw CDIError.unconvertibleLayout("""
                    its filesystem refers to disc address \(lba), which none of its tracks covers
                    """)
            }
            return [UInt8](data)
        }

        func store(_ lba: Int, _ bytes: [UInt8]) throws {
            if patched[lba] == nil, patched.count >= maxPatchedSectors {
                throw CDIError.unconvertibleLayout("""
                    its filesystem describes more than \(maxPatchedSectors) sectors of directories, \
                    which is not a shape a Dreamcast disc has
                    """)
            }
            patched[lba] = bytes
        }

        var pathTables: [(lba: Int, byteCount: Int, bigEndian: Bool)] = []
        var directories: [(lba: Int, byteCount: Int)] = []

        // MARK: Volume descriptors
        //
        // Every descriptor set - the primary, plus any Joliet supplement - names its own path
        // tables and root, and each one has to be corrected or a reader that prefers the
        // supplement will follow stale addresses.
        for index in 0..<maxDescriptors {
            let lba = volumeStart + descriptorSector + index
            var bytes = try sector(lba)
            guard Array(bytes[1..<6]) == identifier else { break }
            if bytes[0] == 255 { break }

            if bytes[0] == 1 || bytes[0] == 2 {
                let pathTableBytes = Int(readLE(bytes, 132))

                // 140 and 144 hold the little-endian tables, 148 and 152 the big-endian ones; the
                // second of each pair is an optional redundant copy and is zero when absent.
                for (offset, bigEndian) in [(140, false), (144, false), (148, true), (152, true)] {
                    let value = Int(bigEndian ? readBE(bytes, offset) : readLE(bytes, offset))
                    guard value != 0 else { continue }
                    pathTables.append((value, pathTableBytes, bigEndian))
                    write(&bytes, offset, value + shift(value), bigEndian: bigEndian)
                }

                // The root's own directory record is embedded in the descriptor at a fixed offset.
                let rootLBA = Int(readLE(bytes, 158))
                directories.append((rootLBA, Int(readLE(bytes, 166))))
                writeBothEndian(&bytes, 158, rootLBA + shift(rootLBA))
            }

            try store(lba, bytes)
        }

        guard !directories.isEmpty else {
            throw CDIError.unconvertibleLayout("""
                it has no ISO 9660 volume descriptor at disc address \(volumeStart + descriptorSector)
                """)
        }

        // MARK: Path tables
        //
        // Records here may straddle a sector boundary, so the table is assembled whole, walked,
        // and cut back into sectors afterwards.
        for table in pathTables {
            let sectors = (table.byteCount + CDIVolume.userDataSize - 1) / CDIVolume.userDataSize
            guard sectors > 0 else { continue }

            var buffer: [UInt8] = []
            for index in 0..<sectors { buffer += try sector(table.lba + index) }

            var offset = 0
            while offset + 8 <= table.byteCount {
                let nameLength = Int(buffer[offset])
                if nameLength == 0 { break }
                let extent = Int(table.bigEndian ? readBE(buffer, offset + 2)
                                                 : readLE(buffer, offset + 2))
                write(&buffer, offset + 2, extent + shift(extent), bigEndian: table.bigEndian)
                // Records are padded to an even length.
                offset += 8 + nameLength + (nameLength % 2)
            }

            for index in 0..<sectors {
                let start = index * CDIVolume.userDataSize
                try store(table.lba + index,
                          Array(buffer[start..<(start + CDIVolume.userDataSize)]))
            }
        }

        // MARK: Directory records
        //
        // Breadth-first from every root found above. Records never cross a sector boundary, so
        // each sector is walked on its own and abandoned at the first zero length.
        var visited: Set<Int> = []
        var queue = directories

        while let directory = queue.popLast() {
            guard visited.insert(directory.lba).inserted else { continue }
            let sectors = (directory.byteCount + CDIVolume.userDataSize - 1) / CDIVolume.userDataSize

            for index in 0..<sectors {
                var bytes = try sector(directory.lba + index)
                var offset = 0

                while offset < bytes.count, bytes[offset] != 0 {
                    let length = Int(bytes[offset])
                    guard length >= 33, offset + length <= bytes.count else { break }

                    let extent = Int(readLE(bytes, offset + 2))
                    let byteCount = Int(readLE(bytes, offset + 10))
                    let isDirectory = bytes[offset + 25] & 0x02 != 0

                    // The two one-byte names are this directory and its parent. Their addresses
                    // still need correcting, but following them would walk in circles.
                    let nameLength = Int(bytes[offset + 32])
                    let isSelfOrParent = nameLength == 1 && bytes[offset + 33] <= 1

                    if isDirectory, !isSelfOrParent { queue.append((extent, byteCount)) }
                    writeBothEndian(&bytes, offset + 2, extent + shift(extent))
                    offset += length
                }

                try store(directory.lba + index, bytes)
            }
        }

        return patched.mapValues { Data($0) }
    }

    // MARK: - Field access

    private static func readLE(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    private static func readBE(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }

    private static func write(_ b: inout [UInt8], _ i: Int, _ value: Int, bigEndian: Bool) {
        let v = UInt32(truncatingIfNeeded: value)
        if bigEndian {
            b[i] = UInt8(v >> 24 & 0xFF); b[i + 1] = UInt8(v >> 16 & 0xFF)
            b[i + 2] = UInt8(v >> 8 & 0xFF); b[i + 3] = UInt8(v & 0xFF)
        } else {
            b[i] = UInt8(v & 0xFF); b[i + 1] = UInt8(v >> 8 & 0xFF)
            b[i + 2] = UInt8(v >> 16 & 0xFF); b[i + 3] = UInt8(v >> 24 & 0xFF)
        }
    }

    /// ISO 9660 records an address twice, little-endian then big-endian, so both copies move.
    private static func writeBothEndian(_ b: inout [UInt8], _ i: Int, _ value: Int) {
        write(&b, i, value, bigEndian: false)
        write(&b, i + 4, value, bigEndian: true)
    }
}
