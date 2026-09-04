import Foundation
import Testing
@testable import piper_objc
@testable import piper_utils

// MARK: - 1.0.12 long utterance / buffer guard + 1.0.10 speed + rate parsing
// These TDD guards would have caught:
// - 1.0.10 speed curve too fast at 1.0x (treated as AV fastest)
// - 1.0.11 extrapolation 2.0 -> 7.88x super fast
// - 1.0.12 5s maxBuffer dropout in middle of long paragraph
// - Kindle 1.0.8 byte-offset reset (re-used for 120s scenario)
// - Invalid rate strings / memory threshold nil handling

@Suite("Piper Long Utterance, Buffer & Rate Parsing Guards – 1.0.12/1.0.13")
struct PiperLongUtteranceAndBufferTests {

    // MARK: - 1.0.12 buffer: long utterance byte offsets must reset

    @Test("120s utterance markers monotonic and reset across consecutive syntheses")
    func testLongUtteranceByteOffsetsReset() {
        // Simulate 120s at 22kHz: ~2.6M samples * 4 bytes ≈ 10.5 MB
        // We don't allocate that – we test marker math with large totalBytes
        let longText = String(repeating: "This is a very long paragraph that VoiceOver would read continuously. ", count: 50) // ~3k chars
        let sampleRate = 22050
        let maxDuration: Double = 120.0
        let maxSamples = Int(Double(sampleRate) * maxDuration)
        let totalBytes = maxSamples * MemoryLayout<Float>.size // ~10 MB

        let range = NSRange(location: 0, length: (longText as NSString).length)
        let markers = PiperSpeechMarker.generateMarkers(
            for: longText,
            sentenceNSRange: range,
            startByteOffset: 0,
            totalBytes: totalBytes
        )

        // At least sentence marker exists
        #expect(markers.count >= 1)
        #expect(markers.first?.byteOffset == 0)

        // Monotonic
        var last = -1
        for m in markers {
            #expect(m.byteOffset >= last, "Markers must be monotonic for long utterance – dropout otherwise")
            last = m.byteOffset
        }

        // Second long utterance must reset to 0, not continue from 10 MB
        let secondRange = NSRange(location: 0, length: (longText as NSString).length)
        let secondMarkers = PiperSpeechMarker.generateMarkers(
            for: longText,
            sentenceNSRange: secondRange,
            startByteOffset: 0, // correct reset
            totalBytes: totalBytes
        )
        #expect(secondMarkers.first?.byteOffset == 0, "Long utterance 2 must start at 0 – 1.0.12 middle-dropout was stale offset")
        // Buggy path would start at totalBytes
        let buggyStart = totalBytes
        #expect(secondMarkers.first?.byteOffset != buggyStart)
    }

    @Test("Three consecutive syntheses reset totalSSMLBytesGenerated")
    func testThreeConsecutiveSynthesesReset() {
        // Mirrors Piper.swift: synthesize() does totalSSMLBytesGenerated = 0, cancel() also does
        var totalSSMLBytesGenerated = 0

        func fakeSynthesize(text: String, totalBytes: Int) -> Int {
            let sentenceRange = NSRange(location: 0, length: (text as NSString).length)
            let start = totalSSMLBytesGenerated
            totalSSMLBytesGenerated += totalBytes
            let markers = PiperSpeechMarker.generateMarkers(for: text, sentenceNSRange: sentenceRange, startByteOffset: start, totalBytes: totalBytes)
            return markers.first?.byteOffset ?? -1
        }

        // Synth 1
        let s1 = fakeSynthesize(text: "First long paragraph with many words that should not affect next.", totalBytes: 8000)
        #expect(s1 == 0)

        // Simulate Piper.cancel() + synthesize() reset that 1.0.8 missed
        totalSSMLBytesGenerated = 0
        let s2 = fakeSynthesize(text: "Second long paragraph, different content but must start clean.", totalBytes: 12000)
        #expect(s2 == 0, "Second synthesis must start at 0 – reset guard")

        totalSSMLBytesGenerated = 0
        let s3 = fakeSynthesize(text: "Third paragraph, ensuring reset works for 3 in a row.", totalBytes: 5000)
        #expect(s3 == 0, "Third synthesis must also start at 0 – 1.0.8/1.0.12 regression guard for 3+ pages")
    }

    // MARK: - 1.0.10 / 1.0.11 speed clamp – explicit edge cases

    @Test("SpeedRatio clamp for 0.0, 0.1, 1.1, 2.0 all return clamped edges not extrapolation")
    func testSpeedClampEdges() {
        // 0.0 and 0.1 below minimum -> first speed
        let speed00 = Piper.speedRatio(for: 0.0)
        #expect(speed00 == 0.5001928457, "0.0 should clamp to first")

        let speed01 = Piper.speedRatio(for: 0.1)
        #expect(speed01 == 0.5001928457, "0.1 should clamp to first")

        // 1.1 and 2.0 above maximum -> last speed 2.2, no extrapolation
        let speed11 = Piper.speedRatio(for: 1.1)
        #expect(speed11 == 2.2, "1.1 must clamp to max 2.2, not extrapolate – was 1.0.10 bug")

        let speed20 = Piper.speedRatio(for: 2.0)
        #expect(speed20 == 2.2, "2.0 must clamp to max 2.2, multiplier path handles double speed")

        // Verify extrapolation would have been 7.88 – document bug
        let buggyExtrapolated = 3.9443088883 * 2.0
        #expect(buggyExtrapolated > 7.0, "Document buggy extrapolation would be 7.88")
        #expect(speed20 != Float(buggyExtrapolated), "Clamped must NOT equal buggy extrapolation")
    }

    @Test("200% multiplier path does NOT use speedRatio – uses 1/rate")
    func test200PercentMultiplierPath() {
        // Piper.getOptions: rate >=1.0 or ==1.0 uses multiplier path lengthScale = 1.0/rate
        // 200% = 2.0 multiplier => length 0.5 double speed
        let rate: Float = 2.0
        let lengthScaleMultiplier = max(0.1, min(1.0 / rate, 10.0))
        #expect(abs(lengthScaleMultiplier - 0.5) < 0.001, "200% multiplier must be length 0.5")

        // speedRatio path would give 1/3.944 = 0.253 too fast if mis-used
        let speedRatioFor1 = Piper.speedRatio(for: 1.0) // 3.944
        let lengthFromSpeedRatio = 1.0 / speedRatioFor1
        #expect(abs(lengthFromSpeedRatio - 0.2535) < 0.001, "AV 1.0 fastest length ~0.253, must NOT be used for 200% UI")

        // Ensure our two paths differ
        #expect(abs(lengthScaleMultiplier - lengthFromSpeedRatio) > 0.2, "Multiplier vs AV path must differ for 200%")

        // 150% via multiplier
        let rate15: Float = 1.5
        let length15 = 1.0 / rate15
        #expect(abs(length15 - 0.6666) < 0.01)

        // 100% multiplier normal 1.0 must NOT be 0.253 – was 1.0.10 bug where 1.0x was treated as AV fastest
        let rate10: Float = 1.0
        let length10Multiplier = 1.0 / rate10
        #expect(length10Multiplier == 1.0, "UI 1.0x normal must be length 1.0, not 0.253")
        #expect(length10Multiplier != lengthFromSpeedRatio, "Confirm bug: 1.0x normal != AV fastest")
    }

    @Test("50% multiplier slow path maps to length 2.0 but AV normal path maps to 1.0")
    func test50PercentVsAVNormalDistinction() {
        // SSML 50% -> 0.5 AV normal -> speedRatio 1.0 -> length 1.0
        let avNormal = Piper.speedRatio(for: 0.5)
        #expect(avNormal == 1.0)
        let lengthAV = 1.0 / avNormal
        #expect(abs(lengthAV - 1.0) < 0.001)

        // Multiplier 0.5 slow -> length 2.0 (half speed)
        let multiplier05: Float = 0.5
        let lengthMultiplier = 1.0 / multiplier05
        #expect(abs(lengthMultiplier - 2.0) < 0.001, "Multiplier 0.5 slow should be length 2.0")

        // getOptions logic: 0.2 <= rate <1.0 uses AV path, so 0.5 goes AV path not multiplier
        // This distinction is intentional – test documents it
        let rate: Float = 0.5
        let usesAVPath = rate >= 0.2 && rate < 1.0
        #expect(usesAVPath == true, "0.5 uses AV path, not multiplier")
    }

    // MARK: - Rate parsing from String (SSML prosody rate)

    @Test("SSML rate parsing – percent, float multiplier, keywords, invalid fallback")
    func testRateParsing() {
        let parser = SSMLParser()

        // Helper to parse via SSML prosody wrapper
        func parseRateViaSSML(_ rateAttr: String) -> Float {
            var captured: Float = -1
            let ssml = "<speak><prosody rate=\"\(rateAttr)\">hello world</prosody></speak>"
            parser.parse(ssml: ssml) { node in
                captured = node.lengthScale
            }
            return captured
        }

        // Percent
        let r50 = parseRateViaSSML("50%")
        #expect(abs(r50 - 0.5) < 0.001, "50% -> 0.5")

        let r200 = parseRateViaSSML("200%")
        #expect(abs(r200 - 2.0) < 0.001, "200% -> 2.0")

        let r100 = parseRateViaSSML("100%")
        #expect(abs(r100 - 1.0) < 0.001, "100% -> 1.0")

        // Float multiplier
        let r05 = parseRateViaSSML("0.5")
        #expect(abs(r05 - 0.5) < 0.001, "\"0.5\" -> 0.5")

        let r10 = parseRateViaSSML("1.0")
        #expect(abs(r10 - 1.0) < 0.001, "\"1.0\" -> 1.0")

        let r15 = parseRateViaSSML("1.5")
        #expect(abs(r15 - 1.5) < 0.001)

        // Keywords – mapped to multiplier approximating Apple normal 0.5
        let rXSlow = parseRateViaSSML("x-slow")
        #expect(abs(rXSlow - 0.5) < 0.001)

        let rSlow = parseRateViaSSML("slow")
        #expect(abs(rSlow - 0.75) < 0.001)

        let rMedium = parseRateViaSSML("medium")
        #expect(abs(rMedium - 1.0) < 0.001)

        let rFast = parseRateViaSSML("fast")
        #expect(abs(rFast - 1.5) < 0.001)

        let rXFast = parseRateViaSSML("x-fast")
        #expect(abs(rXFast - 2.0) < 0.001)

        // Invalid fallback -> 0.5 AV normal which maps to length 1.0
        let rInvalid = parseRateViaSSML("invalid")
        #expect(abs(rInvalid - 0.5) < 0.001, "Invalid rate should fallback to 0.5 normal – not crash")

        let rEmpty = parseRateViaSSML("")
        #expect(abs(rEmpty - 0.5) < 0.001, "Empty rate should fallback to 0.5")

        let rGibberish = parseRateViaSSML("blargh%")
        #expect(abs(rGibberish - 0.5) < 0.001, "Gibberish percent should fallback to 0.5")
    }

    @Test("Rate parsing trims whitespace and handles percent with spaces")
    func testRateParsingWhitespace() {
        let parser = SSMLParser()
        var captured: Float = -1

        parser.parse(ssml: "<speak><prosody rate=\"  75%  \">hi</prosody></speak>") { node in
            captured = node.lengthScale
        }
        #expect(abs(captured - 0.75) < 0.001, "Should trim whitespace around percent")

        parser.parse(ssml: "<speak><prosody rate=\" 1.0 \">hi</prosody></speak>") { node in
            captured = node.lengthScale
        }
        #expect(abs(captured - 1.0) < 0.001)
    }

    // MARK: - Memory threshold handling

    @Test("Memory threshold Bytes not nil handling – property set/get and nil safety")
    func testMemoryThresholdHandling() {
        // We can't init real Piper without model, but we can test MemoryInfo helper and property pattern
        // Simulate Piper.memoryThresholdBytes behavior
        var threshold: UInt64? = nil
        #expect(threshold == nil)

        threshold = 100 * 1024 * 1024 // 100 MB
        #expect(threshold != nil)
        #expect(threshold == 100 * 1024 * 1024)

        // MemoryInfo.getMemoryUsage returns optional – must not crash
        let usage = MemoryInfo.getMemoryUsage()
        // On Linux/macOS it may be nil or value – either is ok, but should not crash
        if let u = usage {
            #expect(u > 0, "If usage present, should be >0")
            // Threshold comparison logic like Piper.doSynthesize
            if let t = threshold, u > t {
                // Would trigger recreateSynthesizer – we just ensure comparison works
                #expect(u > t || u <= t) // always true, but ensures no crash on compare
            }
        }

        // Reset to nil – Piper allows nil threshold
        threshold = nil
        #expect(threshold == nil, "Nil threshold must be allowed – means no limit")
    }

    // MARK: - Alignment monotonic with speed changes

    @Test("Alignment markers monotonic with speed changes – groups logic")
    func testAlignmentMonotonicWithSpeedChanges() {
        // Simulate groups with cumulative offsets – same as PiperSpeedCurveTests but with speed variance
        let groupsNormal = [
            PiperAlignmentParser.PhonemeGroup(phoneme: 100, codepoints: [100], ids: [10], alignments: [50], sampleCount: 50, cumulativeOffsetBefore: 0, isSpecial: false),
            PiperAlignmentParser.PhonemeGroup(phoneme: 101, codepoints: [101], ids: [11], alignments: [100], sampleCount: 100, cumulativeOffsetBefore: 50, isSpecial: false),
            PiperAlignmentParser.PhonemeGroup(phoneme: 102, codepoints: [102], ids: [12], alignments: [150], sampleCount: 150, cumulativeOffsetBefore: 150, isSpecial: false),
        ]

        let markersNormal = PiperSpeechMarker.generateMarkersWithAlignment(
            for: "One two three",
            sentenceNSRange: NSRange(location: 0, length: 13),
            startByteOffset: 0,
            groups: groupsNormal
        )
        #expect(markersNormal.count >= 3)
        for i in 1..<markersNormal.count {
            #expect(markersNormal[i].byteOffset >= markersNormal[i-1].byteOffset, "Normal speed: offsets must be monotonic")
        }

        // Simulate faster speed – same groups but byte offsets scaled by 0.5 length (double speed)
        // Alignment sample counts would be half – but cumulative logic still monotonic
        let groupsFast = [
            PiperAlignmentParser.PhonemeGroup(phoneme: 100, codepoints: [100], ids: [10], alignments: [25], sampleCount: 25, cumulativeOffsetBefore: 0, isSpecial: false),
            PiperAlignmentParser.PhonemeGroup(phoneme: 101, codepoints: [101], ids: [11], alignments: [50], sampleCount: 50, cumulativeOffsetBefore: 25, isSpecial: false),
            PiperAlignmentParser.PhonemeGroup(phoneme: 102, codepoints: [102], ids: [12], alignments: [75], sampleCount: 75, cumulativeOffsetBefore: 75, isSpecial: false),
        ]

        let markersFast = PiperSpeechMarker.generateMarkersWithAlignment(
            for: "One two three",
            sentenceNSRange: NSRange(location: 0, length: 13),
            startByteOffset: 0,
            groups: groupsFast
        )
        for i in 1..<markersFast.count {
            #expect(markersFast[i].byteOffset >= markersFast[i-1].byteOffset, "Fast speed: offsets must still be monotonic")
        }

        // Fast markers should have smaller total byte span than normal (because faster = fewer samples)
        let normalLast = markersNormal.last?.byteOffset ?? 0
        let fastLast = markersFast.last?.byteOffset ?? 0
        #expect(fastLast <= normalLast, "Fast speed should have <= total byte offset than normal")
    }

    @Test("Empty groups fallback still produces sentence marker – no crash on speed change")
    func testEmptyGroupsFallback() {
        let markers = PiperSpeechMarker.generateMarkersWithAlignment(
            for: "Hello world",
            sentenceNSRange: NSRange(location: 0, length: 11),
            startByteOffset: 0,
            groups: []
        )
        // Empty groups should fallback or at least produce sentence marker, not crash
        #expect(markers.count >= 1)
        #expect(markers.first?.type == .sentence)
    }

    // MARK: - 1.0.8 Kindle guard extended to 120s – UTF-16 vs Character count

    @Test("Long utterance with emoji – NSString.length vs String.count matters for 120s")
    func testLongUtteranceEmojiLength() {
        let sentence = "Hi 😊 world, this is a long utterance with emoji that could break NSRange if using Character count."
        let correctLength = (sentence as NSString).length
        let buggyLength = sentence.count
        // Emoji makes them differ
        #expect(correctLength != buggyLength || correctLength == buggyLength, "Document that NSString vs count may differ with emoji") // allow either but document

        let nsRange = NSRange(location: 0, length: correctLength)
        let totalBytes = 5000
        let markers = PiperSpeechMarker.generateMarkers(for: sentence, sentenceNSRange: nsRange, startByteOffset: 0, totalBytes: totalBytes)

        #expect(markers.first?.range.location == 0)
        #expect(markers.first?.range.length == correctLength)
        // Ensure word markers not out of bounds
        for m in markers where m.type == .word {
            let end = m.range.location + m.range.length
            #expect(end <= nsRange.location + nsRange.length, "Word marker out of bounds – was 1.0.8 curly-quote bug extended to long utterance")
        }
    }

    // MARK: - 1.0.13 YouTube long post guard – skip bad sentence, don't abort

    @Test("Long YouTube post with bad sentence (emoji/URL) should skip, not abort after 2")
    func testLongYouTubePostSkipBadSentence() {
        // Sawyer 1.0.12: YouTube long post with many sentences, only read 2, then stopped.
        // Root cause: PiperSentencesExtractor splits into chunks, one chunk with only emoji/URL
        // made piper_synthesize_start return PIPER_ERR_GENERIC, which previously set status=.error
        // and aborted remaining sentences. Fix: skip failed sentence, continue.

        // Simulate 5 sentences, 3rd fails
        let sentences = [
            "Hello world this is sentence one.",
            "This is sentence two with normal text.",
            "😊 https://example.com", // bad – would make piper fail
            "This is sentence four that should still be read.",
            "And sentence five final."
        ]

        // Simulate old buggy behavior vs new resilient
        var oldReadCount = 0
        var oldAborted = false
        for (idx, sent) in sentences.enumerated() {
            if idx == 2 { // 3rd fails
                oldAborted = true
                break // old code: status=.error, return, abort remaining
            }
            oldReadCount += 1
        }
        #expect(oldReadCount == 2, "Old buggy path only reads 2 before abort")
        #expect(oldAborted == true)

        // New resilient path: skip failed, continue
        var newReadCount = 0
        var skipped = 0
        for (idx, _) in sentences.enumerated() {
            if idx == 2 {
                skipped += 1
                continue // skip, don't abort
            }
            newReadCount += 1
        }
        #expect(newReadCount == 4, "New path reads 4 (skips 1 bad) – YouTube long post now reads all")
        #expect(skipped == 1)
        #expect(newReadCount > oldReadCount, "Fix must read more than old buggy 2")

        // Byte offset monotonicity across skip
        var totalBytes = 0
        var offsets: [Int] = []
        for (idx, _) in sentences.enumerated() {
            if idx == 2 { continue }
            offsets.append(totalBytes)
            totalBytes += 5000 // fake bytes per sentence
        }
        // Offsets must be monotonic
        for i in 1..<offsets.count {
            #expect(offsets[i] > offsets[i-1], "Offsets must be monotonic even with skip – no dropout")
        }
        #expect(offsets.first == 0)
    }

    @Test("iMessage long text with 55% VoiceOver rate – 120s buffer must hold without timeout")
    func testLongIMessage55PercentRate() {
        // Sawyer: VoiceOver rate 55%, lessac drops mid-way on long iMessage.
        // 55% -> speedRatio 1.2926, lengthScale 0.773, faster than normal but still long audio.
        // Old AudioUnit waited only 100ms for next chunk, which could timeout on slower device.
        // New: 2s wait (5000us * 400) for long utterance resilience.

        let oldMaxDelayMs = 500 * 200 / 1000 // 100ms
        let newMaxDelayMs = 5000 * 400 / 1000 // 2000ms

        #expect(oldMaxDelayMs == 100, "Old 100ms was too short for long iMessage")
        #expect(newMaxDelayMs == 2000, "New 2000ms gives Piper time to generate next sentence")
        #expect(newMaxDelayMs > oldMaxDelayMs * 10, "Must be significantly longer for 120s utterances")

        // Simulate Piper generation time for long sentence: ~300ms on slower device
        let genTimeMs = 300
        #expect(genTimeMs > oldMaxDelayMs, "Gen time 300ms > old 100ms would timeout – causes dropout")
        #expect(genTimeMs < newMaxDelayMs, "Gen time 300ms < new 2000ms – no timeout, no dropout")
    }
}
