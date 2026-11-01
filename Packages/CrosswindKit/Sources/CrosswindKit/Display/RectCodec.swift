// SPDX-License-Identifier: AGPL-3.0-or-later
import Compression
import Foundation

/// Decodes damage rects: LZ4 raw blocks of premultiplied BGRA rows. Pure and thread-safe so it can be fuzzed.
public enum RectCodec {
    /// The decompressed pixels of a `width` x `height` rect, or nil. The output must be exactly `w*h*4` bytes:
    /// a shorter or longer block, an overflowing size or an empty payload is rejected.
    public static func unpack(width: UInt32, height: UInt32, pixels: Data) -> Data? {
        guard let expected = DisplayLimits.rectBytes(width: width, height: height), expected > 0,
            !pixels.isEmpty, pixels.count <= DisplayLimits.maxCompressedBytes(forRaw: expected)
        else {
            return nil
        }
        // One spare byte: the decoder stops at the capacity, so a block that would produce more than `expected`
        // fills the spare byte and is refused, instead of being silently truncated.
        var out = Data(count: expected + 1)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            pixels.withUnsafeBytes { src -> Int in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self), expected + 1,
                    srcBase.assumingMemoryBound(to: UInt8.self), src.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard written == expected else { return nil }
        out.removeLast()
        return out
    }

    /// Compresses raw BGRA bytes the way the guest does (LZ4 raw). Used by tests to build valid payloads.
    static func pack(_ raw: Data) -> Data? {
        guard !raw.isEmpty else { return nil }
        var out = Data(count: DisplayLimits.maxCompressedBytes(forRaw: raw.count))
        let written = out.withUnsafeMutableBytes { dst -> Int in
            raw.withUnsafeBytes { src -> Int in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                return compression_encode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self), dst.count,
                    srcBase.assumingMemoryBound(to: UInt8.self), src.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard written > 0 else { return nil }
        out.removeSubrange(written...)
        return out
    }
}
