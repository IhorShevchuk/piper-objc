import Foundation
import piper_objc

extension Bundle {
    static var isSetupSwizzling = false
    static func setupSwizzling() {
        if Bundle.isSetupSwizzling {
            return
        }
        Bundle.isSetupSwizzling = true
        let originalSelector = #selector(Bundle.url(forResource:withExtension:))
        let swizzledSelector = #selector(swizzled_url(forResource:withExtension:))

        guard let originalMethod = class_getInstanceMethod(Bundle.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(Bundle.self, swizzledSelector) else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc func swizzled_url(forResource name: String?, withExtension ext: String?) -> URL? {
        if name == "espeak-ng_data" && ext == "bundle" {
            // Check common SPM resource bundle naming conventions
            let candidates = [
                "espeak-ng-spm_espeak-ng-data.bundle",
                "espeak-ng_data.bundle"
            ]
            
            let testBundleURL = Bundle(for: PiperTestAssets.self).bundleURL
            let searchURL = testBundleURL.deletingLastPathComponent()
            
            for candidate in candidates {
                let bundleURL = searchURL.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: bundleURL.path) {
                    return bundleURL
                }
            }
        }
        return self.swizzled_url(forResource: name, withExtension: ext)
    }
}

class PiperTestAssets {
    static let modelBase = "https://huggingface.co/IhorShevchuk/piper1-voices-fp16-quantized/resolve/main"
    static let modelSubPath  = "en/en_US/amy/medium"
    static let modelName = "en_US-amy-medium.onnx"
    static let modelURL = URL(string: "\(modelBase)/\(modelSubPath)/\(modelName)")!
    static let configURL =  URL(string: "\(modelBase)/\(modelSubPath)/\(modelName).json")!

    static var cacheDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("piper_test_assets")
    }

    static var modelPath: String {
        cacheDirectory.appendingPathComponent("model.onnx").path
    }

    static var configPath: String {
        cacheDirectory.appendingPathComponent("model.onnx.json").path
    }

    static var espeakNGDataPath: String {
        // Return empty string to trigger internal automatic installation.
        // Swizzling handles finding the bundle in the test environment.
        return ""
    }

    /// Ensures models are downloaded and returns true if successful
    static func downloadIfNeeded() async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDirectory.path) {
            try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        try await downloadFile(from: modelURL, to: URL(fileURLWithPath: modelPath))
        try await downloadFile(from: configURL, to: URL(fileURLWithPath: configPath))
    }

    private static func downloadFile(from url: URL, to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            return
        }

        print("Downloading test asset from \(url.lastPathComponent)...")
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "PiperTestAssets", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to download asset"])
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}
