//  DreamcastScrambler.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import Foundation

/// The slice shuffle a GD-ROM master applies to a game's boot binary.
///
/// It is a permutation of 32-byte slices, not encryption - the byte histogram is unchanged. A
/// pressed GD-ROM stores the binary shuffled and its bootstrap unshuffles it on load; a self-boot
/// CD-R stores it straight, because the ripper that made the CD-R unshuffled it and patched the
/// bootstrap to match. The bootstrap and the form it expects ship together, so `CDIStager` writes
/// the binary exactly as it finds it and nothing here is used in a conversion. This exists so a
/// test can model a pressed disc and check a staged binary against the one it came from.
nonisolated enum DreamcastScrambler {

    /// Slices are dealt within chunks of this size, largest first.
    private static let maxChunk = 2048 * 1024
    private static let sliceSize = 32

    // MARK: - Shuffling

    /// Returns `data` with its 32-byte slices dealt into the order a GD-ROM master would use.
    static func scramble(_ data: Data) -> Data {
        var output = [UInt8](repeating: 0, count: data.count)
        let input = [UInt8](data)
        var consumed = 0            // bytes of `input` dealt so far
        var chunkStart = 0          // where the chunk being dealt begins in `output`
        var remaining = data.count
        var random = Generator(seed: data.count)

        func deal(_ size: Int) {
            let slices = size / sliceSize
            var order = Array(0..<slices)
            // Fisher-Yates from the top, with the same generator the bootstrap uses. Each draw
            // fixes one destination slice, which is then filled from the next slice of input.
            for i in stride(from: slices - 1, through: 0, by: -1) {
                let pick = (random.next() * i) >> 16
                order.swapAt(i, pick)
                let destination = chunkStart + order[i] * sliceSize
                output.replaceSubrange(destination..<(destination + sliceSize),
                                       with: input[consumed..<(consumed + sliceSize)])
                consumed += sliceSize
            }
        }

        while remaining > maxChunk {
            deal(maxChunk)
            remaining -= maxChunk
            chunkStart += maxChunk
        }
        var size = maxChunk
        while size >= sliceSize {
            while remaining >= size {
                deal(size)
                remaining -= size
                chunkStart += size
            }
            size >>= 1
        }
        // Whatever will not fill a slice is copied straight through.
        if remaining > 0 {
            output.replaceSubrange(chunkStart..<(chunkStart + remaining),
                                   with: input[consumed..<(consumed + remaining)])
        }

        return Data(output)
    }

    /// The generator the bootstrap seeds with the file's length, so both ends deal alike.
    private struct Generator {
        private var state: Int

        init(seed: Int) { state = seed & 0xFFFF }

        mutating func next() -> Int {
            state = (state &* 2109 &+ 9273) & 0x7FFF
            return (state + 0xC000) & 0xFFFF
        }
    }

    // MARK: - Reversing

    /// Undoes `scramble`. Not used in a conversion - it exists so a fixture modeled as pressed can
    /// be read back to the plain binary it was dealt from.
    static func descramble(_ data: Data) -> Data {
        let scrambled = [UInt8](data)
        var output = [UInt8](repeating: 0, count: data.count)
        var produced = 0
        var chunkStart = 0
        var remaining = data.count
        var random = Generator(seed: data.count)

        func undeal(_ size: Int) {
            let slices = size / sliceSize
            var order = Array(0..<slices)
            for i in stride(from: slices - 1, through: 0, by: -1) {
                let pick = (random.next() * i) >> 16
                order.swapAt(i, pick)
                let source = chunkStart + order[i] * sliceSize
                output.replaceSubrange(produced..<(produced + sliceSize),
                                       with: scrambled[source..<(source + sliceSize)])
                produced += sliceSize
            }
        }

        while remaining > maxChunk {
            undeal(maxChunk)
            remaining -= maxChunk
            chunkStart += maxChunk
        }
        var size = maxChunk
        while size >= sliceSize {
            while remaining >= size {
                undeal(size)
                remaining -= size
                chunkStart += size
            }
            size >>= 1
        }
        if remaining > 0 {
            output.replaceSubrange(produced..<(produced + remaining),
                                   with: scrambled[chunkStart..<(chunkStart + remaining)])
        }

        return Data(output)
    }
}
