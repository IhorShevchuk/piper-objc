// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

/// Alignment-aware parsing of `piper_audio_chunk` phoneme/ids/alignments
///
/// # piper.h grouping rule (verbatim)
/// Phonemes will look like [p1, p1, 0, p2, p2, 0, ...] where the same phoneme
/// codepoint is repeated for each id from that phoneme (usually just one id
/// plus pad).
///
/// Groups of repeated codepoints are separated by a 0 so that alignments can
/// be attributed to the correct phoneme. This is accomplished by:
///
/// 1. Read N (repeated) codepoints from phonemes until a 0 is reached (or end)
/// 2. The next N phoneme ids correspond to that phoneme
/// 3. The next N alignments (sample counts) correspond to that phoneme
/// 4. Advance your iterators in the phoneme id and alignment arrays by N
/// 5. Repeat
///
/// - Note: `0` codepoint is separator, not a real phoneme. BOS = 1, PAD = 0, EOS = 2 in id space.
/// - Real phoneme groups may include a PAD id (0) as second element (e.g., [realId, 0]) – they are NOT special.
/// - Special group = every id ∈ {0,1,2}. Those correspond to silence meta tokens and should be ignored for highlighting.
public enum PiperAlignmentParser {

    public struct PhonemeGroup {
        /// Representative codepoint (first of repeated group)
        public let phoneme: UInt32
        /// All codepoints in group (usually same value repeated N times)
        public let codepoints: [UInt32]
        /// N ids from phoneme_ids slice
        public let ids: [Int32]
        /// N alignments (sample counts) – already scaled by hop_length in libpiper
        public let alignments: [Int]
        /// Sum of alignments for this group (samples belonging to this phoneme)
        public let sampleCount: Int
        /// Cumulative offset *before* this group in overall chunk (including specials)
        public let cumulativeOffsetBefore: Int
        /// True if this group is meta (BOS/PAD/EOS) – should be ignored for word highlighting
        public let isSpecial: Bool

        public var cumulativeOffsetAfter: Int { cumulativeOffsetBefore + sampleCount }
    }

    /// Pure-Swift grouping used by tests and by Swift bridging of `piper_audio_chunk`
    public static func group(phonemes: [UInt32], ids: [Int32], alignments: [Int]) -> [PhonemeGroup] {
        var result: [PhonemeGroup] = []
        var pCursor = 0
        var idCursor = 0
        var cumulative = 0

        while pCursor < phonemes.count {
            // Count N until 0 separator
            var n = 0
            while pCursor + n < phonemes.count && phonemes[pCursor + n] != 0 {
                n += 1
            }

            if n == 0 {
                // Zero separator alone – skip
                if pCursor < phonemes.count && phonemes[pCursor] == 0 {
                    pCursor += 1
                    continue
                }
                break
            }

            guard idCursor + n <= ids.count && idCursor + n <= alignments.count else {
                // Malformed – stop gracefully, do not crash
                break
            }

            let cps = Array(phonemes[pCursor ..< pCursor + n])
            let sliceIds = Array(ids[idCursor ..< idCursor + n])
            let sliceAlign = Array(alignments[idCursor ..< idCursor + n])

            let isSpecial: Bool = sliceIds.allSatisfy { $0 >= 0 && $0 <= 2 }

            let group = PhonemeGroup(
                phoneme: cps.first ?? 0,
                codepoints: cps,
                ids: sliceIds,
                alignments: sliceAlign,
                sampleCount: sliceAlign.reduce(0, +),
                cumulativeOffsetBefore: cumulative,
                isSpecial: isSpecial
            )
            result.append(group)
            cumulative += sliceAlign.reduce(0, +)

            pCursor += n
            if pCursor < phonemes.count && phonemes[pCursor] == 0 {
                pCursor += 1 // skip separator
            }
            idCursor += n
        }

        return result
    }

    /// Convenience that also filters specials and returns (phoneme, offset, count)
    public static func phonemeOffsets(from groups: [PhonemeGroup], includeSpecial: Bool = false) -> [(phoneme: UInt32, offset: Int, count: Int)] {
        var out: [(UInt32, Int, Int)] = []
        var running = 0
        for g in groups {
            if !includeSpecial && g.isSpecial {
                running += g.sampleCount
                continue
            }
            out.append((g.phoneme, running, g.sampleCount))
            running += g.sampleCount
        }
        return out
    }

    // MARK: – Helpers

    // (isMeta detection is purely ID-based; codepoint check kept for future if needed)
}

// MARK: - C-struct bridging (unsafe pointers) – production path in Piper.swift
public extension PiperAlignmentParser {

    /// Parse directly from `piper_audio_chunk` raw pointers – safe copy into Swift arrays
    /// - Parameters are the raw fields from C struct; pointers may be nil when counts are 0.
    static func group(
        phonemesPtr: UnsafePointer<UInt32>?,
        numPhonemes: Int,
        idsPtr: UnsafePointer<Int32>?,
        numIds: Int,
        alignmentsPtr: UnsafePointer<Int32>?,
        numAlignments: Int
    ) -> [PhonemeGroup] {
        guard numPhonemes > 0, numIds > 0, numAlignments > 0 else { return [] }
        guard let pPtr = phonemesPtr, let iPtr = idsPtr, let aPtr = alignmentsPtr else { return [] }

        let phonemes = Array(UnsafeBufferPointer(start: pPtr, count: numPhonemes))
        let ids = Array(UnsafeBufferPointer(start: iPtr, count: numIds)).map { Int32($0) }
        let aligns = Array(UnsafeBufferPointer(start: aPtr, count: numAlignments)).map { Int($0) }

        return group(phonemes: phonemes, ids: ids, alignments: aligns)
    }
}
