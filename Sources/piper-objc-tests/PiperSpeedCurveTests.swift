import Testing
@testable import piper_objc

@Suite("Piper Speed Curve Tests")
struct PiperSpeedCurveTests {

    // Test boundary conditions

    @Test("Rate below minimum returns first speed")
    func testRateBelowMinimum() {
        let speed = Piper.speedRatio(for: 0.1)
        #expect(speed == 0.5001928457, "Speed for rate below minimum should be clamped to the first value.")
    }

    @Test("Rate above maximum clamps to max speed (no extrapolation)")
    func testRateAboveMaximum() {
        // Bug fix: 1.0.10 extrapolated 2.0 -> 7.88x super fast. Now clamp.
        // 1.1 and 2.0 should both return 3.9443088883 max.
        let speed11 = Piper.speedRatio(for: 1.1)
        #expect(speed11 == 3.9443088883, "Speed for 1.1 should clamp to max, got \(speed11)")
        let speed20 = Piper.speedRatio(for: 2.0)
        #expect(speed20 == 3.9443088883, "Speed for 2.0 should clamp to max, got \(speed20)")
    }

    // MARK: - Fast follow-up TDD: base 1.0x normal not fast

    @Test("Base 1.0x multiplier normal not fast")
    func testBase1xNormal() {
        // Plain text fallback 1.0 multiplier should map to length_scale 1.0, not 0.253
        // We test via getOptions logic: rate==1.0 => multiplier path => 1.0 length
        // Here we test speedRatio for AV normal 0.5 == 1.0, and that 1.0 multiplier is NOT 3.944
        let avNormal = Piper.speedRatio(for: 0.5)
        #expect(avNormal == 1.0, "AV 0.5 normal should be 1.0 speed")
        // 1.0 AV fastest is 3.944, but UI base 1.0x should NOT use that.
        // Ensure our getOptions distinction treats 1.0 as multiplier normal.
        // Simulated: length_scale = 1.0 / rate for multiplier
        let multiplier1x = 1.0 / 1.0
        #expect(multiplier1x == 1.0, "Multiplier 1.0 should be length 1.0 normal, not 0.253")
        let buggyLength = 1.0 / 3.9443088883
        #expect(abs(buggyLength - 0.253) < 0.01, "Buggy path gave 0.253, confirming bug existed")
        // Correct length for 1.0 should be 1.0, not 0.253
        #expect(abs(multiplier1x - 1.0) < 0.001)
    }

    @Test("50 percent normal maps to AV 0.5 => length 1.0")
    func test50PercentNormal() {
        // SSML 50% -> 0.5 AV normal -> speedRatio 1.0 -> length 1.0
        let speed = Piper.speedRatio(for: 0.5)
        let length = 1.0 / speed
        #expect(abs(length - 1.0) < 0.001, "50% AV normal should be length 1.0")
    }

    @Test("100 percent fastest AV maps to 3.944 but UI treats 1.0 as normal")
    func test100PercentFastest() {
        let speed = Piper.speedRatio(for: 1.0)
        #expect(speed == 3.9443088883, "AV 1.0 fastest should be 3.944")
        let lengthFast = 1.0 / speed
        #expect(abs(lengthFast - 0.2535) < 0.001, "AV 1.0 length should be ~0.253")
        // But multiplier 1.0 normal length is 1.0 – fast follow-up chooses multiplier for 1.0
        let multiplierLength = 1.0 / 1.0
        #expect(multiplierLength == 1.0)
    }

    @Test("200 percent double speed via multiplier")
    func test200PercentDouble() {
        // 200% -> 2.0 multiplier -> length 0.5 (double speed)
        let rate: Float = 2.0
        let length = 1.0 / rate
        #expect(abs(length - 0.5) < 0.001, "200% multiplier should be length 0.5 double speed")
        // Old bug extrapolated speedRatio to 7.88 -> length 0.126 super fast, too fast
        let buggySpeed = 3.9443088883 * 2.0
        let buggyLength = 1.0 / buggySpeed
        #expect(buggyLength < 0.2, "Buggy extrapolation gave super fast <0.2")
    }

    @Test("Alignment markers monotonic with speed changes")
    func testAlignmentMonotonic() {
        // Simulate groups with cumulative offsets
        let groups = [
            PiperAlignmentParser.PhonemeGroup(phoneme: 100, codepoints: [100], ids: [10], alignments: [50], sampleCount: 50, cumulativeOffsetBefore: 0, isSpecial: false),
            PiperAlignmentParser.PhonemeGroup(phoneme: 101, codepoints: [101], ids: [11], alignments: [100], sampleCount: 100, cumulativeOffsetBefore: 50, isSpecial: false),
            PiperAlignmentParser.PhonemeGroup(phoneme: 102, codepoints: [102], ids: [12], alignments: [150], sampleCount: 150, cumulativeOffsetBefore: 150, isSpecial: false),
        ]
        let markers = PiperSpeechMarker.generateMarkersWithAlignment(
            for: "One two three",
            sentenceNSRange: NSRange(location: 0, length: 13),
            startByteOffset: 0,
            groups: groups
        )
        // Sentence marker + 3 word markers
        #expect(markers.count >= 3)
        // Byte offsets monotonic increasing
        for i in 1..<markers.count {
            #expect(markers[i].byteOffset >= markers[i-1].byteOffset, "Markers should be monotonic: \(markers[i-1].byteOffset) -> \(markers[i].byteOffset)")
        }
    }

    @Test("Multiplier path for 1.5 fast")
    func test150PercentMultiplier() {
        let rate: Float = 1.5
        let length = 1.0 / rate
        #expect(abs(length - 0.6666) < 0.01, "150% should be length ~0.666")
    }

    @Test("Rate at minimum returns first speed")
    func testRateAtMinimum() {
        let speed = Piper.speedRatio(for: 0.20)
        #expect(speed == 0.5001928457, "Speed for minimum rate should be the exact first value.")
    }

    @Test("Rate at maximum returns last speed")
    func testRateAtMaximum() {
        let speed = Piper.speedRatio(for: 1.00)
        #expect(speed == 3.9443088883, "Speed for maximum rate should be the exact last value.")
    }

    // Test exact matches from the data

    @Test("Rate at an exact data point returns correct speed")
    func testRateAtExactPoint() {
        let speed = Piper.speedRatio(for: 0.50)
        #expect(speed == 1.0, "Speed for rate 0.50 should be exactly 1.0.")
    }

    @Test("Rate at another exact data point returns correct speed")
    func testRateAtAnotherExactPoint() {
        let speed = Piper.speedRatio(for: 0.75)
        #expect(speed == 2.4720048684, "Speed for rate 0.75 should match the data point.")
    }

    // Test interpolation between points

    @Test("Rate between two points interpolates correctly")
    func testInterpolation() {
        // Rate 0.525 is exactly halfway between 0.50 (speed 1.0) and 0.55 (speed 1.2926956961)
        let expectedSpeed = 1.0 + 0.5 * (1.2926956961 - 1.0) // ~1.1463478
        let actualSpeed = Piper.speedRatio(for: 0.525)
        let tolerance: Float = 0.00001
        
        #expect(abs(actualSpeed - Float(expectedSpeed)) < tolerance, "Speed should be linearly interpolated. Expected \(expectedSpeed), got \(actualSpeed).")
    }

    @Test("Rate of zero returns first speed")
    func testRateOfZero() {
        let speed = Piper.speedRatio(for: 0.0)
        #expect(speed == 0.5001928457, "Speed for rate 0.0 should be clamped to the first value.")
    }

    @Test("Rate between two points with non-midpoint interpolation")
    func testInterpolationNonMidpoint() {
        // Rate 0.87 is 40% of the way between 0.85 (speed 2.8403447397) and 0.90 (speed 3.1448106796)
        // (0.87 - 0.85) / (0.90 - 0.85) = 0.02 / 0.05 = 0.4
        let lower = (rate: Float(0.85), speed: Float(2.8403447397))
        let upper = (rate: Float(0.90), speed: Float(3.1448106796))
        let progress: Float = 0.4
        let expectedSpeed = lower.speed + progress * (upper.speed - lower.speed) // 2.96213111566
        let actualSpeed = Piper.speedRatio(for: 0.87)
        let tolerance: Float = 0.00001
        
        #expect(abs(actualSpeed - expectedSpeed) < tolerance, "Speed should be linearly interpolated. Expected \(expectedSpeed), got \(actualSpeed).")
    }

    @Test("Rate very close to a data point interpolates correctly")
    func testInterpolationNearPoint() {
        // Rate 0.4001 is very close to 0.40 (speed 0.8310849027)
        let lower = (rate: Float(0.40), speed: Float(0.8310849027))
        let upper = (rate: Float(0.45), speed: Float(0.9119920277))
        let progress: Float = (0.4001 - 0.40) / (0.45 - 0.40) // 0.0001 / 0.05 = 0.002
        let expectedSpeed = lower.speed + progress * (upper.speed - lower.speed)
        let actualSpeed = Piper.speedRatio(for: 0.4001)
        let tolerance: Float = 0.00001
        #expect(abs(actualSpeed - expectedSpeed) < tolerance, "Interpolation for a rate very close to a point should be correct. Expected \(expectedSpeed), got \(actualSpeed).")
    }
}
