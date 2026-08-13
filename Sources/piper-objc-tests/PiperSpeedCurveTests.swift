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

    @Test("Rate above maximum returns last speed")
    func testRateAboveMaximum() {
        let speed = Piper.speedRatio(for: 1.1)
        #expect(speed == 3.9443088883, "Speed for rate above maximum should be clamped to the last value.")
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
