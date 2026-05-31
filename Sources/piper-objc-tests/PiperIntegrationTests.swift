import Testing
import Foundation
import piper_objc

@Suite("Piper Integration Tests", .serialized)
struct PiperIntegrationTests {
    
    init() async throws {
        // Download models once for the entire suite
        Bundle.setupSwizzling()
        print("[DEBUG] Starting asset download if needed...")
        try await PiperTestAssets.downloadIfNeeded()
        print("[DEBUG] Model Path: \(PiperTestAssets.modelPath)")
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
        try? FileManager.default.removeItem(atPath: outputPath)
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
    }
}

/// A simple delegate for testing synthesis output.
private final class TestPiperDelegate: NSObject, PiperDelegate, @unchecked Sendable {
    private(set) var receivedSamples = false

    func piperDidReceiveSamples(_ samples: UnsafePointer<Float>, withSize count: Int) {
        if count > 0 {
            receivedSamples = true
        }
    }
}
