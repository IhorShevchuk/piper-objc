import Testing
import Foundation
@testable import piper_objc
import piper_utils

/// A mockable version of Piper that allows us to control memory reporting and observe recreations.
private final class MockPiper: Piper {
    var memoryToReport: UInt64? = nil
    private(set) var recreationCount = 0
    override func getMemoryUsage() -> UInt64? { 
        if let memoryToReport = memoryToReport {
            return memoryToReport
        }
        return MemoryInfo.getMemoryUsage() 
    }
    override func recreateSynthesizer() { 
        recreationCount += 1; super.recreateSynthesizer() 
    }
}

@Suite("Piper Integration Tests", .serialized)
struct PiperIntegrationTests {
    
    init() async throws {
        // Download models once for the entire suite
        Bundle.setupSwizzling()
        try await PiperTestAssets.downloadIfNeeded()
    }

    /// Creates a mock Piper instance for testing.
    private func makeMockPiper() -> MockPiper? {
        return MockPiper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )
    }
    @Test("Piper initializes correctly with downloaded models")
    func testPiperInitialization() {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )
        
        #expect(piper != nil)
    }

    @Test("Piper synthesizes text to a WAV file")
    func testSynthesisToFile() async {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!
        
        let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_output.wav").path
        
        await withCheckedContinuation { continuation in
            piper.synthesize("Hello from testing.", toFileAtPath: outputPath) {
                continuation.resume()
            }
        }
        
        #expect(FileManager.default.fileExists(atPath: outputPath))
        let attributes = try? FileManager.default.attributesOfItem(atPath: outputPath)
        let fileSize = attributes?[.size] as? Int64 ?? 0
        #expect(fileSize > 1024, "WAV file should be significantly larger than a header (found \(fileSize) bytes)")
        try? FileManager.default.removeItem(atPath: outputPath)
    }

    @Test("Piper delivers markers to delegate during synthesis")
    func testMarkerDelegate() async throws {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!
        let delegate = TestPiperDelegate()
        piper.delegate = delegate
        let testString = "Hello world. This is a test."
        piper.synthesize(testString)
        var attempts = 0
        while !piper.completed() && attempts < 20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        let allMarkers = delegate.allMarkers.flatMap { $0 }
        #expect(!allMarkers.isEmpty, "Should have received at least one marker")
        #expect(allMarkers.first?.range.location == 0, "First marker range should start at index 0")
        #expect(allMarkers.filter({ $0.type == .sentence }).count >= 2, "Should get at least one marker per sentence")
    }

    @Test("Plain text synthesis generates sentence and word markers")
    func testWordAndSentenceMarkers() async throws {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!
        let delegate = TestPiperDelegate()
        piper.delegate = delegate
        let testString = "This is a test."

        piper.synthesize(testString)

        var attempts = 0
        while !piper.completed() && attempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        let allMarkers = delegate.allMarkers.flatMap { $0 }
        
        #expect(allMarkers.count == 5, "Expected 1 sentence + 4 word markers, but got \(allMarkers.count)")

        let sentenceMarker = allMarkers.first { $0.type == .sentence }
        let wordMarkers = allMarkers.filter { $0.type == .word }

        #expect(sentenceMarker != nil, "Should have one sentence marker")
        #expect(wordMarkers.count == 4, "Should have four word markers")
        #expect(sentenceMarker?.range == NSRange(location: 0, length: 15))
        #expect(wordMarkers.map { $0.range } == [NSRange(location: 0, length: 4), NSRange(location: 5, length: 2), NSRange(location: 8, length: 1), NSRange(location: 10, length: 5)])
    }

    @Test("SSML synthesis generates correct sentence and word markers")
    func testSSMLWordAndSentenceMarkers() async throws {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!
        let delegate = TestPiperDelegate()
        piper.delegate = delegate
        // The text inside the tags is "This is a test."
        let ssmlString = "<speak>This is a test.</speak>"

        piper.synthesizeSSML(ssmlString, speakerId: 0)

        var attempts = 0
        while !piper.completed() && attempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        let allMarkers = delegate.allMarkers.flatMap { $0 }
        
        #expect(allMarkers.count == 5, "Expected 1 sentence + 4 word markers, but got \(allMarkers.count)")

        let sentenceMarker = allMarkers.first { $0.type == .sentence }
        let wordMarkers = allMarkers.filter { $0.type == .word }.sorted { $0.range.location < $1.range.location }

        #expect(sentenceMarker?.range == NSRange(location: 7, length: 15), "Sentence range should be relative to the full SSML string")
        let expectedWordRanges = [NSRange(location: 7, length: 4), NSRange(location: 12, length: 2), NSRange(location: 15, length: 1), NSRange(location: 17, length: 5)]
        #expect(wordMarkers.map { $0.range } == expectedWordRanges, "Word ranges should be relative to the full SSML string")
    }

    @Test("Piper synthesizes SSML and notifies delegate")
    func testSSMLSynthesis() async throws {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        // Use a simple SSML string with prosody to test both the parser and synthesis pipeline
        let ssml = "<speak>Hello <prosody rate='150%'>world</prosody>!</speak>"
        piper.synthesizeSSML(ssml, speakerId: 0)

        // Wait for completion (status becomes completed).
        // Since this method is asynchronous and delegate-based, we poll the status.
        var attempts = 0
        while !piper.completed() && attempts < 100 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }

        #expect(piper.completed())
        #expect(delegate.receivedSamples, "Delegate should have received audio samples")
        #expect(delegate.totalBytes > 10000, "Should have produced a reasonable amount of audio data")
    }

    @Test("Piper handles cancellation correctly")
    func testSynthesisCancellation() async throws {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        // Long text to ensure we have time to cancel
        let longText = String(repeating: "This is a very long sentence that will take some time to synthesize. ", count: 10)
        
        piper.synthesize(longText)
        
        // Wait slightly for synthesis to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        piper.cancel()
        
        let samplesAfterCancel = delegate.sampleCount
        
        // Wait to see if more samples arrive
        try await Task.sleep(nanoseconds: 500_000_000)
        
        #expect(delegate.sampleCount <= samplesAfterCancel + 1024, "Synthesis should have stopped or finished current small buffer after cancellation")
        #expect(piper.status == .canceled || piper.status == .completed)
    }

    @Test("Prosody rate actually affects sample count")
    func testSSMLRateImpact() async throws {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!

        let delegateNormal = TestPiperDelegate()
        let delegateFast = TestPiperDelegate()

        // 1. Normal Speed
        piper.delegate = delegateNormal
        piper.synthesizeSSML("<speak>Check the speed of this voice.</speak>", speakerId: 0)
        while !piper.completed() { try await Task.sleep(nanoseconds: 100_000_000) }
        let normalCount = delegateNormal.sampleCount

        // 2. Fast Speed (200%)
        piper.delegate = delegateFast
        piper.synthesizeSSML("<speak><prosody rate='200%'>Check the speed of this voice.</prosody></speak>", speakerId: 0)
        while !piper.completed() { try await Task.sleep(nanoseconds: 100_000_000) }
        let fastCount = delegateFast.sampleCount

        #expect(fastCount < normalCount, "Fast rate (\(fastCount)) should produce fewer samples than normal rate (\(normalCount))")
    }

    @Test("Piper handles empty strings gracefully")
    func testEmptyStringSynthesis() async throws {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        piper.synthesize("   ")
        
        var attempts = 0
        while !piper.completed() && attempts < 20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        #expect(piper.completed())
        #expect(delegate.sampleCount == 0, "Should not produce samples for empty whitespace")
    }

    @Test("Piper recreates synthesizer when memory threshold is exceeded")
    func testMemoryThresholdRecreation() async throws {
        let piper = Piper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!

        // Set threshold to 1 byte to guarantee recreation is triggered
        piper.memoryThresholdBytes = 1

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        // Synthesize multiple sentences to trigger the loop checks
        piper.synthesize("First sentence. Second sentence.")

        var attempts = 0
        while !piper.completed() && attempts < 100 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        #expect(piper.completed())
        #expect(delegate.receivedSamples, "Should still successfully produce audio samples after recreation")
        #expect(delegate.sampleCount > 0)
    }

    @Test("Memory threshold contains real memory footprint below a ceiling")
    func testMemoryThresholdContainsFootprint() async throws {
        // This test verifies that setting a memory threshold effectively caps
        // the application's memory footprint below a specified ceiling.

        let longText = String(repeating: "This is a test sentence to generate audio and consume memory. ", count: 50)
        let delegate = TestPiperDelegate()

        // Define a memory ceiling for the test.
        let memoryLimitBytes: UInt64 = 300 * 1024 * 1024 // 300 MB
        let memoryToleranceBytes: UInt64 = 50 * 1024 * 1024 // 50 MB


        // --- Run the test with the memory threshold enabled ---
        let piper = MockPiper(
            modelPath: PiperTestAssets.modelPath,
            configPath: PiperTestAssets.configPath,
            espeakNGData: PiperTestAssets.espeakNGDataPath
        )!
        piper.delegate = delegate
        piper.memoryThresholdBytes = memoryLimitBytes

        piper.synthesize(longText)
        while !piper.completed() { try await Task.sleep(nanoseconds: 10_000_000) }

        guard let finalMemory = MemoryInfo.getMemoryUsage() else {
            #expect(Bool(false), "Could not get final memory usage.")
            return
        }

        // --- Verification ---
        #expect(finalMemory <= memoryLimitBytes + memoryToleranceBytes, "Final memory (\(finalMemory / 1024 / 1024)MB) should not exceed the limit (\(memoryLimitBytes / 1024 / 1024)MB).")
        #expect(piper.recreationCount > 0, "Piper must be recreated at least a few times")
    }

    // MARK: - Memory Management Tests

    @Test("Threshold Not Set: Synthesizer is NOT recreated even with high memory")
    func testThresholdNotSet() async throws {
        guard let piper = makeMockPiper() else {
            #expect(Bool(false), "Failed to initialize MockPiper")
            return
        }

        // Set a high mock memory usage
        piper.memoryToReport = 1_000_000_000 // 1 GB
        // Ensure memoryThresholdBytes is nil (default)
        piper.memoryThresholdBytes = nil

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        piper.synthesize("This is a test.")
        while !piper.completed() { try await Task.sleep(nanoseconds: 100_000_000) }

        #expect(piper.recreationCount == 0, "Synthesizer should not be recreated when threshold is not set.")
        #expect(delegate.sampleCount > 0, "Synthesis should complete successfully.")
    }

    @Test("Threshold Not Exceeded: Synthesizer is NOT recreated")
    func testThresholdNotExceeded() async throws {
        guard let piper = makeMockPiper() else {
            #expect(Bool(false), "Failed to initialize MockPiper")
            return
        }

        piper.memoryToReport = 500 // 500 bytes of memory usage
        piper.memoryThresholdBytes = 1000 // Threshold is 1000 bytes

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        piper.synthesize("This is a test.")
        while !piper.completed() { try await Task.sleep(nanoseconds: 100_000_000) }

        #expect(piper.recreationCount == 0, "Synthesizer should not be recreated when memory is below threshold.")
        #expect(delegate.sampleCount > 0, "Synthesis should complete successfully.")
    }

    @Test("Threshold Exceeded: Synthesizer IS recreated")
    func testThresholdExceeded() async throws {
        guard let piper = makeMockPiper() else {
            #expect(Bool(false), "Failed to initialize MockPiper")
            return
        }

        piper.memoryToReport = 1001 // 1001 bytes of memory usage
        piper.memoryThresholdBytes = 1000 // Threshold is 1000 bytes

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        piper.synthesize("This is a test.")
        while !piper.completed() { try await Task.sleep(nanoseconds: 100_000_000) }

        #expect(piper.recreationCount == 1, "Synthesizer should be recreated once when memory exceeds threshold.")
        #expect(delegate.sampleCount > 0, "Synthesis should complete successfully after recreation.")
    }

    @Test("Threshold Exactly Met: Synthesizer is NOT recreated")
    func testThresholdExactlyMet() async throws {
        guard let piper = makeMockPiper() else {
            #expect(Bool(false), "Failed to initialize MockPiper")
            return
        }

        piper.memoryToReport = 1000 // Exactly 1000 bytes
        piper.memoryThresholdBytes = 1000 // Threshold is 1000 bytes

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        piper.synthesize("This is a test.")
        while !piper.completed() { try await Task.sleep(nanoseconds: 100_000_000) }

        #expect(piper.recreationCount == 0, "Synthesizer should not be recreated when memory exactly meets threshold (uses >).")
        #expect(delegate.sampleCount > 0, "Synthesis should complete successfully.")
    }

    @Test("Zero Threshold: Synthesizer is recreated for each sentence")
    func testZeroThreshold() async throws {
        guard let piper = makeMockPiper() else {
            #expect(Bool(false), "Failed to initialize MockPiper")
            return
        }

        piper.memoryToReport = 1 // Report minimal memory usage
        piper.memoryThresholdBytes = 0 // Threshold is 0, so it will always be exceeded

        let delegate = TestPiperDelegate()
        piper.delegate = delegate

        let text = "First sentence. Second sentence. Third sentence."
        piper.synthesize(text)
        while !piper.completed() { try await Task.sleep(nanoseconds: 100_000_000) }

        #expect(piper.recreationCount == 3, "Synthesizer should be recreated for each of the 3 sentences.")
        #expect(delegate.sampleCount > 0, "Synthesis should complete successfully despite multiple recreations.")
    }
}

/// A simple delegate for testing synthesis output.
private final class TestPiperDelegate: NSObject, PiperDelegate, @unchecked Sendable {
    func piperDidGenerateMarkers(_ markers: [piper_objc.PiperSpeechMarker]) {
        markerLock.lock(); _markers.append(markers); markerLock.unlock()
    }
    
    private let lock = NSLock()
    private var _sampleCount = 0
    private var _receivedSamples = false

    private let markerLock = NSLock()
    private var _markers: [[piper_objc.PiperSpeechMarker]] = []

    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }; return _sampleCount
    }

    var receivedSamples: Bool {
        lock.lock(); defer { lock.unlock() }; return _receivedSamples
    }

    var totalBytes: Int {
        sampleCount * MemoryLayout<Float>.size
    }

    var allMarkers: [[piper_objc.PiperSpeechMarker]] {
        markerLock.lock(); defer { markerLock.unlock() }; return _markers
    }

    func piperDidReceiveSamples(_ samples: UnsafePointer<Float>, withSize count: Int) {
        lock.lock()
        defer { lock.unlock() }
        if count > 0 {
            _receivedSamples = true
            _sampleCount += count
        }
    }
}
