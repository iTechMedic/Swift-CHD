//  CDIVolume.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.
//
//  Just enough of a Dreamcast disc's contents to convert one: where the boot header is, and where
//  the binary it names lives. `CDIImage` says where the tracks are; this says what is inside them.

import Foundation

/// Reads a DiscJuggler image by disc address rather than by track.
///
/// Everything a Dreamcast disc points at - the filesystem's own records included - is an absolute
/// address, so reads here take one and find the track that covers it.
nonisolated struct CDIVolume {

    /// Bytes of user data in a sector, whatever framing the track stores around it.
    static let userDataSize = 2048

    /// What every Dreamcast disc opens its boot header with.
    private static let bootSignature = Array("SEGA SEGAKATANA ".utf8)

    /// Offset within the boot header of the name of the binary to run.
    private static let bootFileNameOffset = 0x60
    private static let bootFileNameLength = 16

    /// Sector of a volume at which ISO 9660 puts its primary descriptor.
    private static let descriptorSector = 16

    private let image: CDIImage
    private let handle: FileHandle

    init(image: CDIImage, handle: FileHandle) {
        self.image = image
        self.handle = handle
    }

    // MARK: - Addressing

    /// The track a Dreamcast boots from: the first one of the last session.
    var bootTrack: CDITrack {
        let lastSession = image.tracks.map(\.session).max() ?? 1
        return image.tracks.first { $0.session == lastSession } ?? image.tracks[0]
    }

    /// The 2048 bytes of user data at an absolute disc address.
    /// - Returns: `nil` when no data track covers `lba`, so callers can report *what* is missing.
    func userData(atLBA lba: Int) throws -> Data? {
        guard let track = image.tracks.first(where: { $0.lbaRange.contains(lba) }),
              let dataOffset = track.userDataOffset else { return nil }

        let offset = track.byteOffset + (lba - track.gdiLBA) * track.sectorSize + dataOffset
        try handle.seek(toOffset: UInt64(offset))
        guard let data = try handle.read(upToCount: Self.userDataSize),
              data.count == Self.userDataSize else { return nil }
        return data
    }

    // MARK: - Boot header

    /// Checks the disc opens with a Dreamcast boot header and returns it.
    func bootHeader() throws -> Data {
        guard let header = try userData(atLBA: bootTrack.gdiLBA) else {
            throw CDIError.notBootable("its last session begins with no readable data sector")
        }
        guard [UInt8](header.prefix(Self.bootSignature.count)) == Self.bootSignature else {
            throw CDIError.notBootable("""
                the first sector of its last session is not a Dreamcast boot header
                """)
        }
        return header
    }

    /// The binary IP.BIN says to run, conventionally `1ST_READ.BIN`.
    func bootFileName() throws -> String {
        let header = try bootHeader()
        let start = Self.bootFileNameOffset
        let raw = header[start..<(start + Self.bootFileNameLength)]
        let name = String(decoding: raw, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw CDIError.notBootable("its boot header names no program to run")
        }
        return name
    }

    // MARK: - Filesystem

    /// Locates the boot binary in the disc's ISO 9660 directory.
    ///
    /// The addresses recorded in the filesystem are absolute, which is what makes the conversion in
    /// `CDIStager` possible at all: the tracks holding the files keep the addresses they had, and
    /// only the boot header is duplicated to where a GD-ROM would keep it.
    /// - Returns: Where the binary starts, and how many bytes long it is.
    func locateBootFile() throws -> (lba: Int, byteCount: Int) {
        let name = try bootFileName()
        let root = try rootDirectory()

        for entry in try directoryEntries(at: root.lba, byteCount: root.byteCount)
        where entry.name.caseInsensitiveCompare(name) == .orderedSame && !entry.isDirectory {
            return (entry.lba, entry.byteCount)
        }

        throw CDIError.notBootable("""
            its boot header names "\(name)", which is not in the disc's root directory
            """)
    }

    /// Every entry in the disc's root directory, and the address each one starts at.
    ///
    /// Used to tell whether the game seeks by address rather than by name - see
    /// `CDIStager.verifyRelocationIsSafe`.
    func rootEntries() throws -> [(name: String, lba: Int)] {
        let root = try rootDirectory()
        let entries = try directoryEntries(at: root.lba, byteCount: root.byteCount)
        return [(".", root.lba)] + entries.map { ($0.name, $0.lba) }
    }

    /// Reads the primary volume descriptor and returns where the root directory sits.
    private func rootDirectory() throws -> (lba: Int, byteCount: Int) {
        let descriptorLBA = bootTrack.gdiLBA + Self.descriptorSector
        guard let descriptor = try userData(atLBA: descriptorLBA) else {
            throw CDIError.notBootable("its filesystem descriptor at sector \(descriptorLBA) "
                                       + "could not be read")
        }
        let bytes = [UInt8](descriptor)
        guard bytes[0] == 1, Array(bytes[1..<6]) == Array("CD001".utf8) else {
            throw CDIError.notBootable("it has no ISO 9660 filesystem where one is expected, "
                                       + "at sector \(descriptorLBA)")
        }

        // The root's own directory record is embedded in the descriptor at a fixed offset.
        let record = Array(bytes[156..<190])
        return (Int(readU32(record, 2)), Int(readU32(record, 10)))
    }

    private struct Entry {
        let name: String
        let lba: Int
        let byteCount: Int
        let isDirectory: Bool
    }

    /// Walks one directory's records. Records never straddle a sector, so each sector is read
    /// whole and abandoned at the first zero length, which is how the format marks the end.
    private func directoryEntries(at lba: Int, byteCount: Int) throws -> [Entry] {
        var entries: [Entry] = []
        let sectors = (byteCount + Self.userDataSize - 1) / Self.userDataSize

        for sector in 0..<sectors {
            guard let data = try userData(atLBA: lba + sector) else { continue }
            let bytes = [UInt8](data)
            var offset = 0

            while offset < bytes.count, bytes[offset] != 0 {
                let length = Int(bytes[offset])
                guard length >= 33, offset + length <= bytes.count else { break }

                let nameLength = Int(bytes[offset + 32])
                guard offset + 33 + nameLength <= bytes.count else { break }

                // Names carry a ";1" version suffix, and the two one-byte names are . and ..
                var name = String(decoding: bytes[(offset + 33)..<(offset + 33 + nameLength)],
                                  as: UTF8.self)
                if let separator = name.firstIndex(of: ";") { name = String(name[..<separator]) }

                entries.append(Entry(name: name,
                                     lba: Int(readU32(bytes, offset + 2)),
                                     byteCount: Int(readU32(bytes, offset + 10)),
                                     isDirectory: bytes[offset + 25] & 0x02 != 0))
                offset += length
            }
        }

        return entries
    }

    private func readU32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
    }
}
