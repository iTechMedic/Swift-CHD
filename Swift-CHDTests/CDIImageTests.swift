//  CDIImageTests.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import XCTest
@testable import Swift_CHD

final class CDIImageTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    private func fixtureURL(_ data: Data) throws -> URL {
        let url = try CDIFixture.write(data)
        scratch.append(url)
        return url
    }

    // MARK: - Parsing

    func testParsesSingleSession() throws {
        let data = CDIFixture.make(sessions: [[
            .audio(lba: 0, length: 400, pregap: 150),
            .audio(lba: 550, length: 300)
        ]])
        let image = try CDIImage.read(at: try fixtureURL(data))

        XCTAssertEqual(image.sessionCount, 1)
        XCTAssertEqual(image.tracks.count, 2)
        XCTAssertEqual(image.tracks.map(\.length), [400, 300])
        XCTAssertEqual(image.tracks.map(\.session), [1, 1])
        XCTAssertEqual(image.tracks.map(\.number), [1, 2])
    }

    func testAssignsTracksToSessions() throws {
        let data = CDIFixture.make(sessions: [
            [.audio(lba: 0, length: 400, pregap: 150), .audio(lba: 550, length: 300)],
            [.mode2(lba: 12_000, length: 500)]
        ])
        let image = try CDIImage.read(at: try fixtureURL(data))

        XCTAssertEqual(image.sessionCount, 2)
        XCTAssertEqual(image.tracks.map(\.session), [1, 1, 2])
        XCTAssertEqual(image.tracks.last?.mode, 2)
        XCTAssertEqual(image.tracks.last?.sectorSize, 2336)
    }

    /// DiscJuggler counts from the lead-in; GDI counts from track 1's user data 150 sectors later.
    func testGDILBADropsTheLeadIn() throws {
        let data = CDIFixture.make(sessions: [
            [.audio(lba: 0, length: 400, pregap: 150)],
            [.mode2(lba: 12_000, length: 500, pregap: 150)]
        ])
        let image = try CDIImage.read(at: try fixtureURL(data))

        XCTAssertEqual(image.tracks[0].gdiLBA, 0)
        XCTAssertEqual(image.tracks[1].gdiLBA, 12_000)
    }

    /// Byte offsets must skip the pregap, which is stored in the file ahead of the track.
    func testByteOffsetSkipsPregap() throws {
        let data = CDIFixture.make(sessions: [[
            .audio(lba: 0, length: 400, pregap: 150),
            .audio(lba: 550, length: 300)
        ]])
        let image = try CDIImage.read(at: try fixtureURL(data))

        XCTAssertEqual(image.tracks[0].byteOffset, 150 * 2352)
        XCTAssertEqual(image.tracks[0].pregapByteOffset, 0)
        XCTAssertEqual(image.tracks[1].byteOffset, (150 + 400) * 2352)
    }

    // MARK: - The byte-accounting invariant

    /// The parse is only trusted when the tracks account for the file exactly. Corrupting a single
    /// length must be rejected rather than producing a plausible-looking but wrong track list.
    func testRejectsTableThatDoesNotAccountForTheFile() throws {
        let data = CDIFixture.make(
            sessions: [[.audio(lba: 0, length: 400, pregap: 150)]],
            corruptTotalLengthBy: -7
        )
        XCTAssertThrowsError(try CDIImage.read(at: try fixtureURL(data))) { error in
            guard case CDIError.corrupt = error else {
                return XCTFail("expected .corrupt, got \(error)")
            }
        }
    }

    // MARK: - Malformed input

    /// Regression: the trailer is two arbitrary words from an untrusted file. A word of 1 put the
    /// table one byte from EOF, and reading the 2-byte session count crashed with "Index out of
    /// range". Every one of these must fail as an error, never a trap.
    func testHostileTrailerWordsDoNotCrash() throws {
        let sizes = [0, 1, 2, 3, 20, 4090, 4095, 4096, 4097,
                     Int(UInt32.max), Int(Int32.max), 0x8000_0000]
        for word in sizes {
            for version: UInt32 in [0x8000_0006, 0x0000_0000, 0xDEAD_BEEF] {
                var data = Data(repeating: 0x42, count: 4096)
                data.replaceSubrange(4088..<4092, with: le(version))
                data.replaceSubrange(4092..<4096, with: le(UInt32(truncatingIfNeeded: word)))
                let url = try fixtureURL(data)
                XCTAssertThrowsError(try CDIImage.read(at: url),
                                     "word=\(word) version=\(version) should not parse")
                XCTAssertFalse(CDIImage.looksLikeDiscJuggler(at: url))
            }
        }
    }

    func testTinyAndEmptyFilesAreRejected() throws {
        for size in [0, 1, 4, 7, 8, 9, 32] {
            let url = try fixtureURL(Data(repeating: 0, count: size))
            XCTAssertThrowsError(try CDIImage.read(at: url), "\(size)-byte file should not parse")
            XCTAssertFalse(CDIImage.looksLikeDiscJuggler(at: url))
        }
    }

    func testMissingFileIsReportedNotCrashed() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("definitely-not-here-\(UUID().uuidString).cdi")
        XCTAssertThrowsError(try CDIImage.read(at: url))
        XCTAssertFalse(CDIImage.looksLikeDiscJuggler(at: url))
    }

    func testDetectsFixtureAsDiscJuggler() throws {
        let data = CDIFixture.make(sessions: [[.audio(lba: 0, length: 400, pregap: 150)]])
        XCTAssertTrue(CDIImage.looksLikeDiscJuggler(at: try fixtureURL(data)))
    }

    private func le(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }
}
