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

    // MARK: - Helpers

    private func write(_ data: Data) throws -> URL {
        let url = try CDIFixture.write(data)
        scratch.append(url)
        return url
    }

    private func stage(_ url: URL) throws -> (CDIStager.Plan, CDIStager.Staged) {
        let image = try CDIImage.read(at: url)
        let plan = try CDIStager.plan(image, from: url)
        let staged = try CDIStager.stage(image, from: url,
                                         progress: { _ in }, isCancelled: { false })
        scratch.append(staged.directory)
        return (plan, staged)
    }

    private func stageDreamcast(
        _ disc: CDIFixture.DreamcastDisc = CDIFixture.dreamcastDisc()
    ) throws -> (CDIFixture.DreamcastDisc, CDIStager.Plan, CDIStager.Staged) {
        let url = try write(CDIFixture.make(sessions: disc.sessions))
        let (plan, staged) = try stage(url)
        return (disc, plan, staged)
    }

    private func trackData(_ staged: CDIStager.Staged, _ track: CDIStager.PlannedTrack) throws -> Data {
        try Data(contentsOf: staged.directory.appendingPathComponent(track.fileName))
    }

    private func readU32(_ data: Data, _ offset: Int) -> Int {
        (0..<4).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
    }

    /// The 2048 bytes of user data a Mode 1 raw sector carries. Re-based, so callers can index
    /// from zero - a `Data` slice otherwise keeps the offsets it was cut at.
    private func userData(_ data: Data, sector: Int) -> Data {
        let start = sector * CDIStager.rawSectorSize + 16
        return Data(data[start..<(start + CDIVolume.userDataSize)])
    }

    // MARK: - Layout

    /// The whole point of the conversion: emulators read a CHD as a GD-ROM and look for the boot
    /// header at a fixed address, so a copy of the boot session has to be waiting there.
    func testPlanCopiesTheBootSessionToTheHighDensityArea() throws {
        let (_, plan, _) = try stageDreamcast()

        XCTAssertEqual(plan.tracks.count, 3)
        XCTAssertEqual(plan.tracks.map(\.lba), [0, 14_296, CDIStager.highDensityLBA])
        XCTAssertEqual(plan.tracks.map(\.number), [1, 2, 3])

        // The copy is the boot session again, not a new track of its own.
        XCTAssertEqual(plan.tracks[1].source, plan.tracks[2].source)
        XCTAssertEqual(plan.tracks[2].length, plan.tracks[1].length)
    }

    /// Every original track keeps its address: the filesystem records absolute ones, so moving a
    /// track would leave every file on the disc pointing at the wrong place.
    func testOriginalTracksKeepTheirAddresses() throws {
        let disc = CDIFixture.dreamcastDisc(bootSessionLBA: 12_000)
        let url = try write(CDIFixture.make(sessions: disc.sessions))
        let image = try CDIImage.read(at: url)
        let plan = try CDIStager.plan(image, from: url)

        for track in image.tracks {
            XCTAssertTrue(plan.tracks.contains { $0.lba == track.gdiLBA && $0.length == track.length },
                          "track at \(track.gdiLBA) must be staged where it was")
        }
    }


    /// Flycast rejects a CHD with fewer than three tracks, so a disc that has fewer of its own
    /// gets filler to sit alongside in the low-density area, which nothing reads.
    func testFillerIsAddedWhenTheDiscHasTooFewTracks() throws {
        // One session holding both the filesystem and the boot header, so only one real track.
        let disc = CDIFixture.dreamcastDisc(bootSessionLBA: nil)
        let url = try write(CDIFixture.make(sessions: disc.sessions))
        let (plan, staged) = try stage(url)

        XCTAssertEqual(plan.tracks.count, 3)
        XCTAssertEqual(plan.tracks[2].lba, CDIStager.highDensityLBA)
        XCTAssertNil(plan.tracks[1].source, "the middle track should be filler")
        XCTAssertFalse(plan.tracks[1].isAudio,
                       "a reader that finds only audio below the high-density area rejects the disc")
        XCTAssertLessThan(plan.tracks[1].lba, CDIStager.highDensityLBA)

        let filler = try trackData(staged, plan.tracks[1])
        XCTAssertEqual(filler.count, plan.tracks[1].length * CDIStager.rawSectorSize)
        XCTAssertFalse(userData(filler, sector: 0).contains { $0 != 0 },
                       "filler carries no data, only sector framing")
    }

    // MARK: - Sector form

    /// redream's and Flycast's CHD readers understand only AUDIO and MODE1_RAW, so Mode 2 sectors
    /// are rewritten as Mode 1 - user data moved to offset 16, where those readers look for it.
    func testDataTracksAreWrittenAsMode1Raw() throws {
        let (disc, plan, staged) = try stageDreamcast()
        let data = try trackData(staged, plan.tracks[0])

        XCTAssertEqual(data[15], 0x01, "mode byte must say Mode 1")

        // The descriptor the fixture placed must come back byte for byte, at the Mode 1 offset.
        XCTAssertEqual(userData(data, sector: 16), CDIFixture.volumeDescriptor())
        XCTAssertEqual(userData(data, sector: CDIFixture.rootDirectoryLBA),
                       CDIFixture.rootDirectory(bootFileLBA: disc.bootFileLBA,
                                                byteCount: disc.bootBinary.count))
    }

    /// The address in a sector header says where that sector now sits. The boot copy is written
    /// from the same source as the boot session but to a different address, so it must be renumbered
    /// rather than carry the address it came from.
    func testSectorHeadersStateTheAddressWrittenTo() throws {
        let (_, plan, staged) = try stageDreamcast()

        func fromBCD(_ byte: UInt8) -> Int { Int(byte >> 4) * 10 + Int(byte & 0x0F) }

        for track in plan.tracks where !track.isAudio {
            let data = try trackData(staged, track)
            let head = [UInt8](data.prefix(16))

            XCTAssertEqual(head[0], 0x00)
            XCTAssertEqual(Array(head[1..<11]), Array(repeating: 0xFF, count: 10))
            XCTAssertEqual(head[11], 0x00)

            let frames = fromBCD(head[12]) * 60 * 75 + fromBCD(head[13]) * 75 + fromBCD(head[14])
            XCTAssertEqual(frames, track.lba + 150,
                           "track \(track.number) must state its own address, once")
        }
    }

    /// Regression guard for the bug that made every converted disc unreadable: a Mode 2 track
    /// declared as MODE1_RAW without moving its user data leaves everything shifted by eight bytes.
    func testUserDataIsNotLeftShiftedByTheMode2Subheader() throws {
        let (disc, plan, staged) = try stageDreamcast()
        let data = try trackData(staged, plan.tracks[0])
        let descriptor = userData(data, sector: 16)

        XCTAssertEqual(descriptor[0], 1, "descriptor type must land on the first byte")
        XCTAssertEqual(Array(descriptor[1..<6]), Array("CD001".utf8))
        XCTAssertEqual(disc.bootFileLBA, CDIFixture.defaultBootFileLBA)
    }

    // MARK: - Relocation

    /// A disc whose own data covers the address a GD-ROM boots from cannot be converted by
    /// copying, so the boot session is moved there and everything else is moved after it.
    private func relocatingDisc(embedOwnAddresses: Bool = false) -> CDIFixture.DreamcastDisc {
        // A second data track lies across the high-density address, so the boot session cannot be
        // copied into place and the disc has to be rebuilt around it instead.
        CDIFixture.dreamcastDisc(
            dataTrackLength: 2_100,
            extraTracks: [.mode2Raw(lba: CDIStager.highDensityLBA - 100, length: 300)],
            addressOffset: 2_000,
            embedOwnAddresses: embedOwnAddresses)
    }

    func testDiscCoveringTheBootAddressIsRelocatedRatherThanRefused() throws {
        let (_, plan, _) = try stageDreamcast(relocatingDisc())

        guard case let .relocate(boot, data) = plan.strategy else {
            return XCTFail("expected a relocation, got \(plan.strategy)")
        }
        XCTAssertEqual(boot, CDIStager.highDensityLBA - 14_296)
        XCTAssertGreaterThan(data, 0)

        // Two filler tracks fill the low-density area, then the boot session, then the data.
        XCTAssertEqual(plan.tracks.count, 5)
        XCTAssertEqual(plan.tracks[0].lba, 0, "track 1 must start at zero or every later "
                       + "address is rebased away from the high-density area")
        XCTAssertEqual(plan.tracks[2].lba, CDIStager.highDensityLBA)
        XCTAssertFalse(plan.tracks[0].isAudio, "a reader finding only audio here rejects the disc")
        XCTAssertTrue(plan.advisory != nil, "a relocated disc has to be flagged for testing")
    }

    /// The point of relocating: the filesystem still finds its files afterwards.
    func testRelocationRewritesTheFilesystemToMatch() throws {
        let disc = relocatingDisc()
        let (_, plan, staged) = try stageDreamcast(disc)

        guard case let .relocate(_, dataShift) = plan.strategy else {
            return XCTFail("expected a relocation")
        }
        let dataTrack = try XCTUnwrap(plan.tracks.first { $0.source?.gdiLBA == 0 })
        let bootTrack = try XCTUnwrap(plan.tracks.first { $0.lba == CDIStager.highDensityLBA })

        // The descriptor the emulator reads, at sector 16 of the high-density area.
        let descriptor = userData(try trackData(staged, bootTrack), sector: 16)
        XCTAssertEqual(Array(descriptor[1..<6]), Array("CD001".utf8))
        let rootExtent = readU32(descriptor, 158)
        XCTAssertEqual(rootExtent, CDIFixture.rootDirectoryLBA + 2_000 + dataShift)
        XCTAssertNotEqual(dataShift, 0)

        // And the record in that directory has moved with it.
        let data = try trackData(staged, dataTrack)
        let root = userData(data, sector: rootExtent - dataTrack.lba)
        let bootRecordExtent = readU32(root, 34 + 34 + 2)
        XCTAssertEqual(bootRecordExtent, disc.bootFileLBA + dataShift)
        XCTAssertEqual(plan.bootFile.range.lowerBound, disc.bootFileLBA + dataShift)
    }

    /// Both halves of an ISO 9660 address have to move, or a reader that trusts the big-endian
    /// copy follows an address that is still pointing at the old disc.
    func testRelocationRewritesBothEndianCopiesOfAnAddress() throws {
        let (_, plan, staged) = try stageDreamcast(relocatingDisc())
        let bootTrack = try XCTUnwrap(plan.tracks.first { $0.lba == CDIStager.highDensityLBA })
        let descriptor = userData(try trackData(staged, bootTrack), sector: 16)

        let littleEndian = readU32(descriptor, 158)
        let bigEndian = (0..<4).reduce(0) { $0 << 8 | Int(descriptor[162 + $1]) }
        XCTAssertEqual(bigEndian, littleEndian)
    }

    /// A game that reads the disc by raw sector number cannot survive being moved, and no amount
    /// of filesystem rewriting helps, so such a disc is refused rather than quietly broken.
    func testDiscThatSeeksByRawAddressIsRefused() throws {
        let disc = relocatingDisc(embedOwnAddresses: true)
        let url = try write(CDIFixture.make(sessions: disc.sessions))
        let image = try CDIImage.read(at: url)

        XCTAssertThrowsError(try CDIStager.plan(image, from: url)) { error in
            guard case let CDIError.unconvertibleLayout(detail) = error else {
                return XCTFail("expected unconvertibleLayout, got \(error)")
            }
            XCTAssertTrue(detail.contains("raw address"), detail)
            XCTAssertTrue(detail.contains(CDIFixture.bootFileName), detail)
        }
    }

    /// A GD-ROM has room for only `highDensityLBA` sectors below its boot header, so a CD's
    /// soundtrack ends up above it, where no Dreamcast plays audio from. Measured on Neo XYX: the
    /// CDI plays in both emulators, every CHD of it stops at its first screen.
    func testDiscWithCDAudioIsRefused() throws {
        let disc = CDIFixture.dreamcastDisc(
            extraTracks: [.audio(lba: 20_000, length: 300)])
        let url = try write(CDIFixture.make(sessions: disc.sessions))
        let image = try CDIImage.read(at: url)

        XCTAssertThrowsError(try CDIStager.plan(image, from: url)) { error in
            XCTAssertEqual(error as? CDIError, .hasCDAudio(trackCount: 1))
        }
    }

    /// The refusal is about the disc, not about whether it would have been rebuilt: a build of
    /// Neo XYX that relocated nothing failed identically, so a disc that could be converted by
    /// copying alone is refused just the same.
    func testCDAudioIsRefusedEvenWhenNothingWouldMove() throws {
        let disc = CDIFixture.dreamcastDisc(
            extraTracks: [.audio(lba: 20_000, length: 300)])
        let url = try write(CDIFixture.make(sessions: disc.sessions))
        let image = try CDIImage.read(at: url)

        // Same disc, waived: it plans, and by copying rather than relocating.
        let plan = try CDIStager.plan(image, from: url, allowingRiskyConversion: true)
        XCTAssertEqual(plan.strategy, .copyBootSession)
    }

    /// A disc that needs no moving must not be moved: copying is always the safer conversion.
    func testDiscWithRoomForTheBootCopyIsNotRelocated() throws {
        let (_, plan, _) = try stageDreamcast()
        XCTAssertEqual(plan.strategy, .copyBootSession)
        XCTAssertTrue(plan.sectorOverrides.isEmpty)
        XCTAssertNil(plan.advisory)
    }

    // MARK: - The boot binary

    /// What is being written is a GD-ROM, and the bootstrap that reads one unshuffles the binary
    /// on load - so a self-boot CD-R's straight binary has to be shuffled on the way in, or the
    /// bootstrap unshuffles bytes that were never dealt and runs garbage.
    func testBootBinaryIsShuffledOnTheWayIn() throws {
        let (disc, plan, staged) = try stageDreamcast()

        XCTAssertEqual(try stagedBootBinary(disc, plan, staged),
                       DreamcastScrambler.scramble(disc.bootBinary))
    }

    /// The shuffle is applied to whatever the source stored, without inspecting it. An earlier
    /// version guessed from the byte statistics whether a binary was already shuffled; the guess
    /// was wrong on real discs, so the format decides and the contents are not consulted.
    func testShufflingDoesNotDependOnHowTheSourceStoredIt() throws {
        let disc = CDIFixture.dreamcastDisc(scrambleBootBinary: true)
        let (_, plan, staged) = try stageDreamcast(disc)

        let asStored = DreamcastScrambler.scramble(disc.bootBinary)
        XCTAssertEqual(try stagedBootBinary(disc, plan, staged),
                       DreamcastScrambler.scramble(asStored))
    }

    /// The boot binary as it reached the staged disc, read back out of track 1.
    private func stagedBootBinary(_ disc: CDIFixture.DreamcastDisc,
                                  _ plan: CDIStager.Plan,
                                  _ staged: CDIStager.Staged) throws -> Data {
        let data = try trackData(staged, plan.tracks[0])
        var binary = Data()
        for sector in 0..<disc.bootFileSectors {
            binary.append(userData(data, sector: disc.bootFileLBA + sector))
        }
        return binary
    }

    /// `scramble` is a permutation, so a fixture modeled as pressed can always be read back to the
    /// plain binary it was dealt from.
    func testScramblingRoundTrips() throws {
        let binary = CDIFixture.bootBinary(sectors: 40)
        XCTAssertEqual(DreamcastScrambler.descramble(DreamcastScrambler.scramble(binary)), binary)
    }

    // MARK: - Output shape

    func testGDIListsEveryTrackWithItsAbsoluteLBA() throws {
        let (_, plan, staged) = try stageDreamcast()
        let gdi = try String(contentsOf: staged.gdiURL, encoding: .utf8)
        let lines = gdi.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.first, "\(plan.tracks.count)")
        XCTAssertEqual(lines.count, plan.tracks.count + 1)
        // trackNumber, LBA, type (0 audio / 4 data), sector size, file, offset
        XCTAssertEqual(lines[1], "1 0 4 2352 track01.bin 0")
        XCTAssertEqual(lines[3], "3 \(CDIStager.highDensityLBA) 4 2352 track03.bin 0")
    }

    func testEveryTrackIsWrittenAtFullSectorSize() throws {
        let (_, plan, staged) = try stageDreamcast()
        for track in plan.tracks {
            let size = try trackData(staged, track).count
            XCTAssertEqual(size, track.length * CDIStager.rawSectorSize, "size of \(track.fileName)")
        }
    }

    /// Track filenames must not inherit the disc's title: chdman's GDI parser splits on
    /// whitespace, so a space in the name would break the sheet.
    func testStagedFileNamesContainNoSpaces() throws {
        let (_, _, staged) = try stageDreamcast()
        let names = try FileManager.default.contentsOfDirectory(atPath: staged.directory.path)
        for name in names {
            XCTAssertFalse(name.contains(" "), "\(name) contains a space")
        }
    }

    func testStagedSizeMatchesWhatIsWritten() throws {
        let (_, plan, staged) = try stageDreamcast()
        var written = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: staged.directory.path)
        where name != "disc.gdi" {
            let url = staged.directory.appendingPathComponent(name)
            written += try XCTUnwrap(
                FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        }
        XCTAssertEqual(Int64(written), CDIStager.stagedSize(of: plan))
    }

    // MARK: - Refusals

    func testCancellationStopsStagingAndRemovesTheDirectory() throws {
        let disc = CDIFixture.dreamcastDisc(dataTrackLength: 8_000)
        let url = try write(CDIFixture.make(sessions: disc.sessions))
        let image = try CDIImage.read(at: url)

        // Other tests keep their staged directories until tearDown, so count rather than expect
        // none: what matters is that the cancelled run leaves nothing of its own behind.
        func stagingDirectories() -> Set<String> {
            let temp = FileManager.default.temporaryDirectory
            let names = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
            return Set(names.filter { $0.hasPrefix("swiftchd-cdi-") })
        }
        let before = stagingDirectories()

        XCTAssertThrowsError(
            try CDIStager.stage(image, from: url, progress: { _ in }, isCancelled: { true })
        ) { error in
            XCTAssertEqual(error as? CDIError, .cancelled)
        }

        XCTAssertEqual(stagingDirectories().subtracting(before), [],
                       "a cancelled run must clean up after itself")
    }

    func testUnsupportedTrackShapeIsRejectedBeforeReading() throws {
        // Audio is only meaningful at 2352 bytes per sector.
        let bogus = CDIFixture.TrackSpec(mode: 0, sectorSizeCode: 0, pregap: 150, length: 10, lba: 0)
        let url = try write(CDIFixture.make(sessions: [[bogus]]))
        let image = try CDIImage.read(at: url)

        XCTAssertThrowsError(try CDIStager.plan(image, from: url)) { error in
            guard case CDIError.unsupportedTrack = error else {
                return XCTFail("expected .unsupportedTrack, got \(error)")
            }
        }
    }

    /// A CDI holding some other system's disc has no boot header, and no CHD layout to become.
    func testImageWithoutABootHeaderIsRefused() throws {
        let url = try write(CDIFixture.make(sessions: [
            [.audio(lba: 0, length: 40, pregap: 150)],
            [.mode2Raw(lba: 5_000, length: 20)]
        ]))
        let image = try CDIImage.read(at: url)

        XCTAssertThrowsError(try CDIStager.plan(image, from: url)) { error in
            guard case CDIError.notBootable = error else {
                return XCTFail("expected .notBootable, got \(error)")
            }
        }
    }
}
