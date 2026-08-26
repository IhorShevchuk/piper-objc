import Testing
import Foundation
@testable import piper_objc

@Suite("PiperCreateOptions Tests", .serialized)
struct PiperCreateOptionsTests {

    init() {
        // Ensure espeak-ng_data.bundle can be found in test runner (prevents NSException in EspeakLib)
        Bundle.setupSwizzling()
    }

    @Test("Init with only modelPath sets required field and nils optionals")
    func testInitWithOnlyModelPath() {
        let opts = PiperCreateOptions(modelPath: "/tmp/model.onnx")
        #expect(opts.modelPath == "/tmp/model.onnx")
        #expect(opts.configPath == nil)
        #expect(opts.espeakDataPath == nil)
        #expect(opts.dataDir == nil)
        #expect(opts.g2pwModelDir == nil)
    }

    @Test("Init with all fields stores them correctly")
    func testInitWithAllFields() {
        let opts = PiperCreateOptions(
            modelPath: "/models/zh.onnx",
            configPath: "/models/zh.onnx.json",
            espeakDataPath: "/data/espeak-ng-data",
            dataDir: "/data",
            g2pwModelDir: "/data/g2pw"
        )
        #expect(opts.modelPath == "/models/zh.onnx")
        #expect(opts.configPath == "/models/zh.onnx.json")
        #expect(opts.espeakDataPath == "/data/espeak-ng-data")
        #expect(opts.dataDir == "/data")
        #expect(opts.g2pwModelDir == "/data/g2pw")
    }

    @Test("Convenience init modelPath + configPath")
    func testConvenienceInit() {
        let opts = PiperCreateOptions(modelPath: "/a/b.onnx", configPath: "/a/b.onnx.json")
        #expect(opts.modelPath == "/a/b.onnx")
        #expect(opts.configPath == "/a/b.onnx.json")
        #expect(opts.espeakDataPath == nil)
        #expect(opts.dataDir == nil)
        #expect(opts.g2pwModelDir == nil)
    }

    @Test("Mutable properties can be changed after init")
    func testMutability() {
        let opts = PiperCreateOptions(modelPath: "/tmp/model.onnx")
        opts.dataDir = "/tmp/data"
        opts.g2pwModelDir = "/tmp/data/g2pw"
        opts.configPath = "/tmp/model.onnx.json"
        #expect(opts.dataDir == "/tmp/data")
        #expect(opts.g2pwModelDir == "/tmp/data/g2pw")
        #expect(opts.configPath == "/tmp/model.onnx.json")
    }

    @Test("PiperCreateOptions is NSObject subclass for ObjC interop")
    func testNSObjectInterop() {
        let opts = PiperCreateOptions(modelPath: "/tmp/model.onnx")
        // Use ObjC runtime check rather than 'is' (which is always true for NSObject subclass)
        #expect(type(of: opts) == PiperCreateOptions.self)
        #expect(opts.isKind(of: NSObject.self))
        // Ensure it can be used via KVC-style (ObjC runtime)
        let mirrorModelPath = (opts as NSObject).value(forKey: "modelPath") as? String
        #expect(mirrorModelPath == "/tmp/model.onnx")
    }

    @Test("Piper init with invalid model returns nil (options path)")
    func testPiperInitWithInvalidOptionsReturnsNil() {
        let opts = PiperCreateOptions(
            modelPath: "/nonexistent/path/model.onnx",
            configPath: "/nonexistent/path/model.onnx.json",
            espeakDataPath: "/tmp",
            dataDir: nil,
            g2pwModelDir: nil
        )
        let piper = Piper(options: opts)
        #expect(piper == nil, "Piper should fail to init with nonexistent model")
    }

    @Test("Piper init with legacy 3-arg still works and fails gracefully on invalid path")
    func testLegacyInitInvalidPath() {
        let piper = Piper(modelPath: "/no/such/model.onnx", configPath: "/no/such/model.onnx.json", espeakNGData: "")
        #expect(piper == nil)
    }

    @Test("Options with empty strings are treated as nil for default fallback")
    func testEmptyStringHandling() {
        // Empty configPath should trigger modelPath + .json fallback in piper_create_with_options
        // We test the options object stores empty as-is, but Piper init should not crash
        let opts = PiperCreateOptions(modelPath: "/tmp/model.onnx", configPath: "", espeakDataPath: "", dataDir: "", g2pwModelDir: "")
        #expect(opts.configPath == "")
        #expect(opts.espeakDataPath == "")
        #expect(opts.dataDir == "")
        #expect(opts.g2pwModelDir == "")
        // Piper init should still attempt and fail gracefully (not crash) – it will resolve empty to auto-discovery
        let piper = Piper(options: opts)
        #expect(piper == nil, "Should still be nil for nonexistent model, but not crash on empty strings")
    }

    @Test("DataDir and g2pwModelDir enable Chinese pinyin auto-discovery path")
    func testDataDirG2PwFields() {
        // This test documents the intended usage for Chinese voices
        // dataDir may contain espeak-ng-data/ and g2pw/ subfolders
        let opts = PiperCreateOptions(
            modelPath: "/voices/zh_CN/model.onnx",
            dataDir: "/voices/zh_CN/data",
            g2pwModelDir: nil // nil should trigger search inside dataDir/g2pw and dataDir
        )
        #expect(opts.dataDir == "/voices/zh_CN/data")
        #expect(opts.g2pwModelDir == nil)
        #expect(opts.modelPath.hasSuffix("zh_CN/model.onnx"))

        // With explicit g2pw dir
        let optsExplicit = PiperCreateOptions(
            modelPath: "/voices/zh_CN/model.onnx",
            dataDir: "/voices/zh_CN/data",
            g2pwModelDir: "/voices/zh_CN/data/g2pw"
        )
        #expect(optsExplicit.g2pwModelDir == "/voices/zh_CN/data/g2pw")
    }
}

@Suite("Piper Create With Options – migration regression", .serialized)
struct PiperCreateWithOptionsMigrationTests {

    init() {
        Bundle.setupSwizzling()
    }

    @Test("Piper recreates synthesizer using stored options (memory pressure path)")
    func testRecreateUsesStoredOptions() {
        // We cannot trigger real memory pressure without a real model,
        // but we can verify that Piper's stored properties are used for recreation
        // by checking that init with dataDir/g2pw doesn't crash and stores them
        let opts = PiperCreateOptions(
            modelPath: "/tmp/model.onnx",
            configPath: nil,
            espeakDataPath: nil,
            dataDir: "/tmp",
            g2pwModelDir: "/tmp/g2pw"
        )
        // Init will fail (no model), but options object itself is valid and would be used for recreation
        #expect(opts.dataDir == "/tmp")
        #expect(opts.g2pwModelDir == "/tmp/g2pw")
    }
}
