//  SwiftCHDTaskTests.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import XCTest
@testable import Swift_CHD

final class SwiftCHDTaskTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftCHDTaskTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeFile(_ name: String, executable: Bool) throws -> String {
        let path = folder.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644],
                                              ofItemAtPath: path)
        return path
    }

    // MARK: - resolveExecutable

    func testExecutableFileResolvesToItself() throws {
        let chdman = try makeFile("chdman", executable: true)
        XCTAssertEqual(SwiftCHDTask.resolveExecutable(chdman), chdman)
    }

    func testFolderResolvesToTheChdmanInside() throws {
        let chdman = try makeFile("chdman", executable: true)
        XCTAssertEqual(SwiftCHDTask.resolveExecutable(folder.path), chdman)
        XCTAssertEqual(SwiftCHDTask.resolveExecutable(folder.path + "/"), chdman)
    }

    func testFolderWithoutChdmanIsRejected() {
        // Folders pass isExecutableFile, and launching one fails with EACCES (issue #11).
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: folder.path))
        XCTAssertNil(SwiftCHDTask.resolveExecutable(folder.path))
    }

    func testNonExecutableFileIsRejected() throws {
        let chdman = try makeFile("chdman", executable: false)
        XCTAssertNil(SwiftCHDTask.resolveExecutable(chdman))
    }

    func testMissingOrBlankPathIsRejected() {
        XCTAssertNil(SwiftCHDTask.resolveExecutable(folder.appendingPathComponent("nope").path))
        XCTAssertNil(SwiftCHDTask.resolveExecutable("  "))
    }

    // MARK: - run

    func testRunGivenAFolderWithoutChdmanReportsNotFoundRatherThanEACCES() async {
        do {
            try await SwiftCHDTask().run(chdmanPath: folder.path, arguments: []) { _, _ in }
            XCTFail("expected an error")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, SwiftCHDTask.errorDomain)
            XCTAssertEqual(error.code, SwiftCHDTask.ErrorCode.executableNotFound.rawValue)
        }
    }
}
