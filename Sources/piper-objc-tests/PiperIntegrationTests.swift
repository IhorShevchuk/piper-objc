import Testing
import Foundation
import piper_objc

@Suite("Piper Integration Tests", .serialized)
struct PiperIntegrationTests {
    
    init() async throws {
        // Download models once for the entire suite
        Bundle.setupSwizzling()
        try await PiperTestAssets.downloadIfNeeded()
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
        #expect(allMarkers.count >= 2, "Should get at least one marker per sentence")
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
