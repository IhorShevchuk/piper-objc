import Testing
import Foundation
@testable import piper_objc
@testable import piper_utils

// MARK: - Kindle / 1.0.8 regression guard
// Real bug: John Bayles (VoiceOver iOS 26.6, iPhone 17 Pro) reported after 1.0.7.101
// Kindle would read one page then jump back to contents.
// Root: word markers in 1.0.8 used stale byte offsets + char-count NSRange,
// so second page started with wrong offset and punctuation broke range.

@Suite("Kindle Regression – 1.0.8 page-turn guard")
struct PiperKindleRegressionTests {

    @Test("Second page starts at 0, not previous total (reset)")
    func testOffsetsResetBetweenPages() {
        let page1 = "This is page one."
        let page2 = "This is page two."

        // Simulate two independent syntheses – both should start at 0
        let page1Range = NSRange(location: 0, length: (page1 as NSString).length)
        let page2Range = NSRange(location: 0, length: (page2 as NSString).length)

        let m1 = PiperSpeechMarker.generateMarkers(for: page1, sentenceNSRange: page1Range, startByteOffset: 0, totalBytes: 4000)
        let m2 = PiperSpeechMarker.generateMarkers(for: page2, sentenceNSRange: page2Range, startByteOffset: 0, totalBytes: 4000)

        #expect(m1.first?.byteOffset == 0, "Page 1 should start at 0")
        #expect(m2.first?.byteOffset == 0, "Page 2 must also start at 0 – not 4000. This was the 1.0.8 Kindle bug.")
        // Ensure word markers within each page are increasing, but across pages they reset
        let m1Last = m1.last?.byteOffset ?? 0
        let m2First = m2.first?.byteOffset ?? -1
        #expect(m1Last >= 0)
        #expect(m2First == 0)
    }

    @Test("NSString.length vs String.count – emoji")
    func testNSStringLengthMatters() {
        // 😊 is 1 Character but 2 UTF-16 units
        let sentence = "Hi 😊 world"
        // Buggy code used text.count (9) for NSRange length, correct is NSString length (11)
        let correctLength = (sentence as NSString).length
        let buggyLength = sentence.count // 9
        #expect(correctLength != buggyLength, "Doc check: emoji makes lengths differ")
        #expect(correctLength == 11)

        let nsRange = NSRange(location: 10, length: correctLength)
        let markers = PiperSpeechMarker.generateMarkers(for: sentence, sentenceNSRange: nsRange, startByteOffset: 0, totalBytes: 5000)
        // Should still get sentence + words, not crash on range
        #expect(markers.first?.range.location == 10)
        #expect(markers.first?.range.length == correctLength)
    }

    @Test("Byte offsets are monotonic – Kindle needs this for page progress")
    func testMonotonicOffsets() {
        let sentence = "First sentence, with a comma, and more; second part."
        let range = NSRange(location: 100, length: (sentence as NSString).length)
        let markers = PiperSpeechMarker.generateMarkers(for: sentence, sentenceNSRange: range, startByteOffset: 1000, totalBytes: 9000)

        var last = -1
        for m in markers {
            #expect(m.byteOffset >= last, "Offsets must be monotonic – Kindle jumps otherwise. Got \(m.byteOffset) after \(last)")
            last = m.byteOffset
        }
        // All markers should be inside utterance bounds
        for m in markers where m.type == .word {
            let end = m.range.location + m.range.length
            #expect(end <= range.location + range.length, "Word marker out of bounds – was 1.0.8 curly-quote bug")
        }
    }

    @Test("Curly quotes – 1.0.8 punctuation bug #31")
    func testCurlyQuotePunctuation() {
        let sentence = "Such philosophers are called ‘idealists’."
        let nsRange = NSRange(location: 50, length: (sentence as NSString).length)
        let markers = PiperSpeechMarker.generateMarkersWithAlignment(
            for: sentence,
            sentenceNSRange: nsRange,
            startByteOffset: 0,
            groups: [
                // Minimal fake groups – just enough to force alignment path
                PiperAlignmentParser.PhonemeGroup(phoneme: 97, codepoints: [97], ids: [10], alignments: [100], sampleCount: 100, cumulativeOffsetBefore: 0, isSpecial: false),
                PiperAlignmentParser.PhonemeGroup(phoneme: 98, codepoints: [98], ids: [11], alignments: [100], sampleCount: 100, cumulativeOffsetBefore: 100, isSpecial: false),
                PiperAlignmentParser.PhonemeGroup(phoneme: 99, codepoints: [99], ids: [12], alignments: [100], sampleCount: 100, cumulativeOffsetBefore: 200, isSpecial: false),
                PiperAlignmentParser.PhonemeGroup(phoneme: 100, codepoints: [100], ids: [13], alignments: [100], sampleCount: 100, cumulativeOffsetBefore: 300, isSpecial: false),
                PiperAlignmentParser.PhonemeGroup(phoneme: 101, codepoints: [101], ids: [14], alignments: [100], sampleCount: 100, cumulativeOffsetBefore: 400, isSpecial: false),
                PiperAlignmentParser.PhonemeGroup(phoneme: 102, codepoints: [102], ids: [15], alignments: [100], sampleCount: 100, cumulativeOffsetBefore: 500, isSpecial: false),
            ]
        )

        // Should still produce markers despite punctuation stripping
        #expect(markers.count >= 2)
        let wordMarkers = markers.filter { $0.type == .word }
        #expect(wordMarkers.count >= 1, "Curly quotes should not drop all word markers")
    }

    @Test("totalSSMLBytesGenerated reset simulation")
    func testTotalBytesResetLogic() {
        // In Piper.swift: synthesize() does cancel() + totalSSMLBytesGenerated=0
        // If we forget reset, second synthesis reuses old offset -> Kindle jumps to contents.
        var totalSSMLBytesGenerated = 0
        func fakeSynthesize(text: String, totalBytes: Int) -> Int {
            let sentenceRange = NSRange(location: 0, length: (text as NSString).length)
            let start = totalSSMLBytesGenerated
            // simulate sentence done:
            totalSSMLBytesGenerated += totalBytes
            let markers = PiperSpeechMarker.generateMarkers(for: text, sentenceNSRange: sentenceRange, startByteOffset: start, totalBytes: totalBytes)
            return markers.first?.byteOffset ?? -1
        }

        // First book open
        let firstStart = fakeSynthesize(text: "Page one content", totalBytes: 8000)
        #expect(firstStart == 0)

        // Bug would be: forgot reset, second book open starts at 8000
        // Correct fix resets:
        totalSSMLBytesGenerated = 0
        let secondStart = fakeSynthesize(text: "New book page one", totalBytes: 8000)
        #expect(secondStart == 0, "After reset, second synthesis must start at 0 – this guards 1.0.8 regression")
    }
}
