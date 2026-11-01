// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

@testable import CrosswindKit

/// Deterministic PRNG for fuzz-style tests: a failing seed reproduces exactly.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func bytes(_ count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8.random(in: 0...255, using: &self) }
    }
}

/// Values that sit on or just past the edges of the limits, plus extremes that overflow naive arithmetic.
enum EdgeValues {
    static let sizes: [UInt32] = [
        0, 1, 2, 59, 60, 961, 16_383, 16_384, 16_385, 4096, 8192, 65_535, 1 << 20, UInt32.max - 1, UInt32.max,
    ]
    static let scales: [UInt32] = [0, 1, 59, 60, 120, 240, 960, 961, UInt32.max]
}

/// One damage rect as the guest would send it: position, size and compressed payload length.
struct RectSpec {
    var x: UInt32
    var y: UInt32
    var w: UInt32
    var h: UInt32
    var bytes: Int
}

/// A uniformly random value, or one of the edge values half the time.
func biased(_ edges: [UInt32], max: UInt32, _ rng: inout SplitMix64) -> UInt32 {
    Bool.random(using: &rng) ? edges.randomElement(using: &rng)! : UInt32.random(in: 0...max, using: &rng)
}

/// Builds a display frame from raw numbers, for fuzzing `DisplayLimits.checkFrame`.
func makeFrame(width: UInt32, height: UInt32, scale: UInt32, rects: [RectSpec]) -> Crosswind_Display_Frame {
    .with {
        $0.window = 1
        $0.width = width
        $0.height = height
        $0.scale120 = scale
        $0.damage = rects.map { rect in
            .with {
                $0.x = rect.x
                $0.y = rect.y
                $0.width = rect.w
                $0.height = rect.h
                $0.pixels = Data(count: rect.bytes)
            }
        }
    }
}

/// A complete gzip container around raw DEFLATE data (header without optional fields, CRC and size zeroed).
func gzipContainer(deflate payload: Data) -> Data {
    var out = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3])
    out.append(payload)
    out.append(Data(count: 8))
    return out
}

func deflate(_ raw: Data) -> Data? {
    try? (raw as NSData).compressed(using: .zlib) as Data
}
