import Testing
import Foundation
@testable import piper_objc
@testable import piper_utils

// MARK: - TDD tests for alignment grouping rule from piper.h
// Uses production parser `PiperAlignmentParser` (pure Swift) which mirrors C grouping rule

@Suite("Piper Alignment Parser Tests – grouping rule from piper.h")
struct PiperAlignmentParserTests {

    @Test("Groups phonemes by 0 separator, N ids & alignments per group")
    func testBasicGrouping() {
        // phonemes: [a,a,0,b,0,c,c,0] -> 3 groups N=2,1,2
        let phonemes: [UInt32] = [97, 97, 0, 98, 0, 99, 99, 0] // a=97,b=98,c=99
        let ids: [Int32] = [1, 0, 5, 7, 8] // N=2 BOS+PAD, N=1 real, N=2 real+real
        let alignments: [Int] = [100, 50, 200, 150, 60]

        let groups = PiperAlignmentParser.group(phonemes: phonemes, ids: ids, alignments: alignments)

        #expect(groups.count == 3, "Expected 3 phoneme groups")
        #expect(groups[0].codepoints == [97,97])
        #expect(groups[0].ids == [1,0])
        #expect(groups[0].alignments == [100,50])
        #expect(groups[0].sampleCount == 150)
        #expect(groups[0].cumulativeOffsetBefore == 0)

        #expect(groups[1].codepoints == [98])
        #expect(groups[1].ids == [5])
        #expect(groups[1].sampleCount == 200)
        #expect(groups[1].cumulativeOffsetBefore == 150)

        #expect(groups[2].codepoints == [99,99])
        #expect(groups[2].sampleCount == 210)
        #expect(groups[2].cumulativeOffsetBefore == 350)
    }

    @Test("BOS/PAD/EOS groups are marked special and ignored for highlighting")
    func testSpecialFiltering() {
        let phonemes: [UInt32] = [UInt32(94), UInt32(94), 0, 97, 0] // '^','^' BOS, 'a'
        let ids: [Int32] = [1, 0, 10] // BOS=1,PAD=0, real=10
        let alignments = [30, 20, 300]

        let groups = PiperAlignmentParser.group(phonemes: phonemes, ids: ids, alignments: alignments)

        #expect(groups.count == 2)
        #expect(groups[0].isSpecial == true, "BOS+PAD group should be special")
        #expect(groups[1].isSpecial == false)

        let filtered = PiperAlignmentParser.phonemeOffsets(from: groups, includeSpecial: false)
        #expect(filtered.count == 1, "Only real phoneme should remain")
        #expect(filtered[0].phoneme == 97)
        #expect(filtered[0].offset == 50, "Offset should include BOS silence before first real phoneme")
    }

    @Test("Empty chunk returns empty groups")
    func testEmptyChunk() {
        let groups = PiperAlignmentParser.group(phonemes: [], ids: [], alignments: [])
        #expect(groups.isEmpty)
    }

    @Test("Multi-codepoint pinyin phoneme grouping (private-use area)")
    func testPinyinMultiCodepoint() {
        let pinyinCP: UInt32 = 0xE000
        let phonemes: [UInt32] = [pinyinCP, pinyinCP, 0]
        let ids: [Int32] = [15, 0]
        let alignments = [180, 20]

        let groups = PiperAlignmentParser.group(phonemes: phonemes, ids: ids, alignments: alignments)
        #expect(groups.count == 1)
        #expect(groups[0].codepoints.allSatisfy({ $0 == pinyinCP }))
        #expect(groups[0].sampleCount == 200)
    }

    @Test("Cumulative offsets sum including PAD")
    func testCumulativeOffsets() {
        let phonemes: [UInt32] = [101, 101, 0, 102, 102, 0]
        let ids: [Int32] = [12, 0, 13, 0]
        let alignments = [100, 25, 120, 30]

        let groups = PiperAlignmentParser.group(phonemes: phonemes, ids: ids, alignments: alignments)
        let offsets = PiperAlignmentParser.phonemeOffsets(from: groups, includeSpecial: true)
        #expect(offsets[0].offset == 0)
        #expect(offsets[0].count == 125)
        #expect(offsets[1].offset == 125)
        #expect(offsets[1].count == 150)
    }
}

@Suite("Word Marker Alignment Mapping – punctuation cases #31")
struct AlignmentWordMarkerTests {

    @Test("Punctuation apostrophe retains word ranges (#31 example)")
    func testApostropheHighlight() {
        let sentence = "Such philosophers are called ‘idealists’."
        let nsRange = NSRange(location: 0, length: (sentence as NSString).length)
        let markers = PiperSpeechMarker.generateMarkers(for: sentence, sentenceNSRange: nsRange, startByteOffset: 0, totalBytes: 4400)

        let wordMarkers = markers.filter { $0.type == .word }
        #expect(wordMarkers.count >= 5, "Should have markers for each word even with curly quotes")

        var lastOffset = -1
        for m in wordMarkers {
            #expect(m.byteOffset >= lastOffset, "Byte offsets must be monotonic")
            lastOffset = m.byteOffset
        }

        let idealistsRange = (sentence as NSString).range(of: "idealists")
        #expect(idealistsRange.location != NSNotFound, "idealists substring must exist")
        let hasIdealistsMarker = wordMarkers.contains { NSIntersectionRange($0.range, idealistsRange).length > 0 }
        #expect(hasIdealistsMarker, "Should have marker covering 'idealists' despite surrounding punctuation")
    }

    @Test("Em-dash and semicolon don't break markers")
    func testEmDashSemicolon() {
        let sentence = "First sentence, with a comma, and more; second sentence: with colons"
        let nsRange = NSRange(location: 10, length: (sentence as NSString).length)
        let markers = PiperSpeechMarker.generateMarkers(for: sentence, sentenceNSRange: nsRange, startByteOffset: 100, totalBytes: 8000)
        let wordMarkers = markers.filter { $0.type == .word }
        #expect(wordMarkers.count >= 8)
        #expect(wordMarkers.first?.range.location == 10)
    }

    @Test("Word markers prefer alignment-derived sample offsets when available")
    func testAlignmentPreferredPath() {
        let groups = [
            PiperAlignmentParser.PhonemeGroup(
                phoneme: 104,
                codepoints: [104, 104],
                ids: [12, 0],
                alignments: [100, 20],
                sampleCount: 120,
                cumulativeOffsetBefore: 0,
                isSpecial: false
            ),
            PiperAlignmentParser.PhonemeGroup(
                phoneme: 101,
                codepoints: [101],
                ids: [13],
                alignments: [100],
                sampleCount: 100,
                cumulativeOffsetBefore: 120,
                isSpecial: false
            ),
            PiperAlignmentParser.PhonemeGroup(
                phoneme: 119,
                codepoints: [119],
                ids: [14],
                alignments: [120],
                sampleCount: 120,
                cumulativeOffsetBefore: 220,
                isSpecial: false
            ),
            PiperAlignmentParser.PhonemeGroup(
                phoneme: 111,
                codepoints: [111, 111],
                ids: [15, 0],
                alignments: [90, 30],
                sampleCount: 120,
                cumulativeOffsetBefore: 340,
                isSpecial: false
            ),
        ]

        let sentence = "Hello world"
        let nsRange = NSRange(location: 0, length: (sentence as NSString).length)

        let markers = PiperSpeechMarker.generateMarkersWithAlignment(
            for: sentence,
            sentenceNSRange: nsRange,
            startByteOffset: 0,
            groups: groups
        )

        #expect(markers.count >= 3, "Sentence + 2 word markers expected")
        let wordMarkers = markers.filter { $0.type == .word }
        #expect(wordMarkers.count == 2, "Two word markers for Hello and world")
        #expect(wordMarkers[0].byteOffset == 0, "First word at offset 0")
        #expect(wordMarkers[1].byteOffset == 880, "Second word offset derived from alignment, not char proportion")
    }
}
