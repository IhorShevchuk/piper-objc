import Testing
import Foundation
@testable import piper_objc

@Suite("PiperSpeechMarker Tests")
struct PiperSpeechMarkerTests {

    @Test("Generates sentence and word markers correctly")
    func testBasicMarkerGeneration() {
        let sentence = "Hello world."
        let sentenceRange = NSRange(location: 10, length: 12)
        let startOffset = 1000
        let totalBytes = 8800 // e.g., 2200 samples * 4 bytes/sample

        let markers = PiperSpeechMarker.generateMarkers(
            for: sentence,
            sentenceNSRange: sentenceRange,
            startByteOffset: startOffset,
            totalBytes: totalBytes
        )

        #expect(markers.count == 3, "Should generate 1 sentence marker + 2 word markers")

        // Test Sentence Marker
        let sentenceMarker = markers[0]
        #expect(sentenceMarker.type == .sentence)
        #expect(sentenceMarker.range == sentenceRange)
        #expect(sentenceMarker.byteOffset == startOffset)

        // Test "Hello" marker
        let helloMarker = markers[1]
        #expect(helloMarker.type == .word)
        #expect(helloMarker.range == NSRange(location: 10, length: 5)) // "Hello"
        #expect(helloMarker.byteOffset == startOffset)

        // Test "world." marker
        let worldMarker = markers[2]
        #expect(worldMarker.type == .word)
        #expect(worldMarker.range == NSRange(location: 16, length: 6)) // "world."
        
        // Check byte offset distribution
        let helloBytes = Int(Double(totalBytes) * (5.0 / 11.0)) // "Hello" is 5 of 11 chars
        #expect(worldMarker.byteOffset == startOffset + helloBytes)
    }

    @Test("Handles empty sentence")
    func testEmptySentence() {
        let markers = PiperSpeechMarker.generateMarkers(
            for: "  ",
            sentenceNSRange: NSRange(location: 0, length: 2),
            startByteOffset: 0,
            totalBytes: 100
        )

        #expect(markers.count == 1)
        #expect(markers[0].type == .sentence)
    }

    @Test("Handles sentence with no valid words")
    func testSentenceWithOnlyPunctuation() {
        let markers = PiperSpeechMarker.generateMarkers(
            for: ".!?",
            sentenceNSRange: NSRange(location: 5, length: 3),
            startByteOffset: 100,
            totalBytes: 200
        )

        #expect(markers.count == 2)
        #expect(markers[0].type == .sentence)
        #expect(markers[0].range == NSRange(location: 5, length: 3))
    }
    
    @Test("Handles zero total bytes")
    func testZeroTotalBytes() {
        let markers = PiperSpeechMarker.generateMarkers(for: "Hello", sentenceNSRange: .init(location: 0, length: 5), startByteOffset: 0, totalBytes: 0)
        #expect(markers.count == 1, "Should only return a sentence marker if totalBytes is zero")
        #expect(markers[0].type == .sentence)
    }
}
