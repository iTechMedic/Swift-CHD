//  CDIStagerTests.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import XCTest
@testable import Swift_CHD

final class CDIStagerTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    private func stageFixture(_ sessions: [[CDIFixture.TrackSpec]]) throws -> (CDIImage, CDIStager.Staged) {
        let url = try CDIFixture.write(CDIFixture.make(sessions: sessions))
        scratch.append(url)
        let image = try CDIImage.read(at: url)
        let staged = try CDIStager.stage(image, from: url, progress: { _ in }, isCancelled: { false })
        scratch.append(staged.directory)
        return (image, staged)
    }

    // MARK: - Output shape

    func testWritesOneRawFilePerTrackAtFullSectorSize() throws {
        let (image, staged) = try stageFixture([
            [.audio(lba: 0, length: 40, pregap: 150), .audio(lba: 190, length: 30)],
            [.mode2(lba: 5_000, length: 20)]
        ])

        for track in image.tracks {
            let name = track.isAudio ? String(format: "track%02d.raw", track.number)
                                     : String(format: "track%02d.bin", track.number)
            let url = staged.directory.appendingPathComponent(name)
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
            // Every track is written as raw 2352-byte sectors, whatever it was stored as.
            XCTAssertEqual(size, track.length * CDIStager.rawSectorSize, "size of \(name)")
        }
    }

    func testGDIListsEveryTrackWithItsAbsoluteLBA() throws {
        let (image, staged) = try stageFixture([
            [.audio(lba: 0, length: 40, pregap: 150)],
            [.mode2(lba: 5_000, length: 20)]
        ])
        let gdi = try String(contentsOf: staged.gdiURL, encoding: .utf8)
        let lines = gdi.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.first, "\(image.tracks.count)")
        XCTAssertEqual(lines.count, image.tracks.count + 1)
        // trackNumber, LBA, type (0 audio / 4 data), sector size, file, offset
        XCTAssertEqual(lines[1], "1 0 0 2352 track01.raw 0")
        XCTAssertEqual(lines[2], "2 5000 4 2352 track02.bin 0")
    }

    /// Track filenames must not inherit the disc's title: chdman's GDI parser splits on
    /// whitespace, so a space in the name would break the sheet.
    func testStagedFileNamesContainNoSpaces() throws {
        let (_, staged) = try stageFixture([[.audio(lba: 0, length: 10, pregap: 150)]])
        let names = try FileManager.default.contentsOfDirectory(atPath: staged.directory.path)
        for name in names {
            XCTAssertFalse(name.contains(" "), "\(name) contains a space")
        }
    }

    // MARK: - Sector reconstruction

    /// Regression guard. The address written into a sector header is the absolute one, counted
    /// from the lead-in - `track.lba + track.pregap`, which already includes the 150-frame offset.
    /// Adding 150 again here would shift every data sector and break the filesystem inside.
    func testSectorHeaderEncodesAbsoluteAddressWithoutDoubleOffset() throws {
        let lba = 5_000
        let (image, staged) = try stageFixture([
            [.audio(lba: 0, length: 10, pregap: 150)],
            [.mode2(lba: lba, length: 20, pregap: 150)]
        ])
        let dataTrack = try XCTUnwrap(image.tracks.last)
        let url = staged.directory.appendingPathComponent(String(format: "track%02d.bin", dataTrack.number))
        let head = [UInt8](try Data(contentsOf: url).prefix(16))

        // 12-byte sync pattern.
        XCTAssertEqual(head[0], 0x00)
        XCTAssertEqual(Array(head[1..<11]), Array(repeating: 0xFF, count: 10))
        XCTAssertEqual(head[11], 0x00)

        func fromBCD(_ b: UInt8) -> Int { Int(b >> 4) * 10 + Int(b & 0x0F) }
        let frames = fromBCD(head[12]) * 60 * 75 + fromBCD(head[13]) * 75 + fromBCD(head[14])

        XCTAssertEqual(frames, dataTrack.gdiLBA + 150, "header must encode gdiLBA + 150, once")
        XCTAssertEqual(frames, dataTrack.lba + dataTrack.pregap,
                       "which is exactly DiscJuggler's lead-in-inclusive address")
        XCTAssertEqual(frames, lba + 150, "no second 150-frame offset may be applied")
        XCTAssertEqual(head[15], 2, "mode byte must survive as Mode2")
    }

    func testMode2SubheaderIsPreservedFrom2336Sectors() throws {
        let (image, staged) = try stageFixture([
            [.audio(lba: 0, length: 10, pregap: 150)],
            [.mode2(lba: 5_000, length: 5, pregap: 150)]
        ])
        let track = try XCTUnwrap(image.tracks.last)
        XCTAssertEqual(track.sectorSize, 2336)
        let url = staged.directory.appendingPathComponent(String(format: "track%02d.bin", track.number))
        let bytes = [UInt8](try Data(contentsOf: url).prefix(2352))
        // The fixture fills payload bytes with 0xAB; the 2336 bytes must follow the 16-byte header.
        XCTAssertEqual(Array(bytes[16..<24]), Array(repeating: 0xAB, count: 8))
    }

    // MARK: - Sizing and cancellation

    func testStagedSizeMatchesWhatIsWritten() throws {
        let (image, staged) = try stageFixture([[.audio(lba: 0, length: 40, pregap: 150)]])
        var written = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: staged.directory.path)
        where name != "disc.gdi" {
            let url = staged.directory.appendingPathComponent(name)
            written += try XCTUnwrap(
                FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        }
        XCTAssertEqual(Int64(written), CDIStager.stagedSize(of: image))
    }

    func testCancellationStopsStagingAndRemovesTheDirectory() throws {
        let url = try CDIFixture.write(CDIFixture.make(sessions: [[
            .audio(lba: 0, length: 4_000, pregap: 150)
        ]]))
        scratch.append(url)
        let image = try CDIImage.read(at: url)

        var seen: URL?
        XCTAssertThrowsError(
            try CDIStager.stage(image, from: url, progress: { _ in }, isCancelled: { true })
        ) { error in
            XCTAssertEqual(error as? CDIError, .cancelled)
        }
        if let seen { XCTAssertFalse(FileManager.default.fileExists(atPath: seen.path)) }
    }

    func testUnsupportedTrackShapeIsRejectedBeforeWriting() throws {
        // Audio is only meaningful at 2352 bytes per sector.
        let bogus = CDIFixture.TrackSpec(mode: 0, sectorSizeCode: 0, pregap: 150, length: 10, lba: 0)
        let url = try CDIFixture.write(CDIFixture.make(sessions: [[bogus]]))
        scratch.append(url)
        let image = try CDIImage.read(at: url)

        XCTAssertThrowsError(
            try CDIStager.stage(image, from: url, progress: { _ in }, isCancelled: { false })
        ) { error in
            guard case CDIError.unsupportedTrack = error else {
                return XCTFail("expected .unsupportedTrack, got \(error)")
            }
        }
    }
}
