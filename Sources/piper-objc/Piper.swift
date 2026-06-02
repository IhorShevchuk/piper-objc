import Foundation
import piper_utils
import piper
import libespeak_ng

@objc public protocol PiperDelegate: AnyObject {
    func piperDidReceiveSamples(_ samples: UnsafePointer<Float>, withSize count: Int)
}

@objc public enum PiperStatus: Int {
    case created
    case rendering
    case completed
    case error
    case canceled
}

@objcMembers
public class Piper: NSObject {
    private var synthesizer: OpaquePointer?
    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private let ssmlParser = SSMLParser()
    private var _status: PiperStatus = .created
    private let statusLock = NSLock()

    public weak var delegate: PiperDelegate?

    public var status: PiperStatus {
        get {
            statusLock.lock()
            defer { statusLock.unlock() }
            return _status
        }
        set {
            statusLock.lock()
            defer { statusLock.unlock() }
            _status = newValue
        }
    }

    private static let espeakOnce: Void = {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        // Assuming EspeakLib is bridged from the espeak-ng bundle module
        // and follows the naming convention found in the project.
        try? EspeakLib.ensureBundleInstalled(inRoot: URL(fileURLWithPath: documentsPath))
    }()

    private static func ensureEspeakLibDataInstalled() -> String {
        _ = espeakOnce
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    }

    public init?(modelPath: String, andConfigPath modelConfigPath: String) {
        let espeakNGData = Piper.ensureEspeakLibDataInstalled()
        super.init()
        self.operationQueue.name = "\(type(of: self))Queue"
        
        guard let syn = piper_create(modelPath, modelConfigPath, espeakNGData) else {
            return nil
        }
        self.synthesizer = syn
        self.status = .created
    }

    public init?(modelPath: String, configPath: String, espeakNGData: String) {
        super.init()
        self.operationQueue.name = "\(type(of: self))Queue"
        
        let espeakData = espeakNGData.isEmpty ? Piper.ensureEspeakLibDataInstalled() : espeakNGData
        guard let syn = piper_create(modelPath, configPath, espeakData) else {
            return nil
        }
        self.synthesizer = syn
        self.status = .created
    }

    deinit {
        cancel()
        if let syn = synthesizer {
            piper_free(syn)
        }
    }

    public func completed() -> Bool {
        return status == .completed
    }

    public func cancel() {
        status = .canceled
        operationQueue.cancelAllOperations()
        operationQueue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - Synthesis

    public func synthesize(_ text: String) {
        addClearBeforeStartingOperation()
        
        operationQueue.addOperation { [weak self] in
            guard let self = self, let syn = self.synthesizer else { return }
            let options = piper_default_synthesize_options(syn)
            self.doSynthesize(text: text, options: options) { chunk in
                self.delegate?.piperDidReceiveSamples(chunk.samples, withSize: Int(chunk.num_samples))
            }
        }
        
        addMarkAsCompleteOperation(nil)
    }

    public func synthesize(_ text: String, toFileAtPath path: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.synthesize(text, toFileAtPath: path) {
                continuation.resume()
            }
        }
    }

    public func synthesize(_ text: String, toFileAtPath path: String, completion: (() -> Void)? = nil) {
        addClearBeforeStartingOperation()
        
        operationQueue.addOperation { [weak self] in
            guard let self = self, let syn = self.synthesizer else { return }
            let options = piper_default_synthesize_options(syn)
            self.doSynthesizeToFile(text: text, path: path, options: options)
        }
        
        addMarkAsCompleteOperation(completion)
    }

    public func synthesizeSSML(_ ssml: String, speakerId: Int32) {
        addClearBeforeStartingOperation()
        
        operationQueue.addOperation { [weak self] in
            guard let self = self else { return }
            let fragments = self.ssmlParser.parse(ssml: ssml)
            for fragment in fragments {
                autoreleasepool {
                    let options = self.getOptions(for: fragment, speakerId: speakerId)
                    self.doSynthesize(text: fragment.text, options: options) { chunk in
                        self.delegate?.piperDidReceiveSamples(chunk.samples, withSize: Int(chunk.num_samples))
                    }
                }
            }
        }
        
        addMarkAsCompleteOperation(nil)
    }

    public func synthesizeSSML(_ ssml: String, speakerId: Int32, toFileAtPath path: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.synthesizeSSML(ssml, speakerId: speakerId, toFileAtPath: path) {
                continuation.resume()
            }
        }
    }

    public func synthesizeSSML(_ ssml: String, speakerId: Int32, toFileAtPath path: String, completion: (() -> Void)? = nil) {
        addClearBeforeStartingOperation()
        
        operationQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            let pathURL = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: pathURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: path, contents: nil)
            
            guard let fileHandle = try? FileHandle(forWritingTo: pathURL) else { return }
            defer { try? fileHandle.close() }

            var isHeaderWritten = false
            let fragments = self.ssmlParser.parse(ssml: ssml)
            
            for fragment in fragments {
                autoreleasepool {
                    let options = self.getOptions(for: fragment, speakerId: speakerId)
                    self.doSynthesize(text: fragment.text, options: options) { chunk in
                        if !isHeaderWritten {
                            try? self.writeWavHeader(to: fileHandle, sampleRate: Int32(chunk.sample_rate))
                            isHeaderWritten = true
                        }
                        let buffer = UnsafeBufferPointer(start: chunk.samples, count: Int(chunk.num_samples))
                        fileHandle.write(Data(buffer: buffer))
                    }
                }
            }
        }
        
        addMarkAsCompleteOperation(completion)
    }

    // MARK: - Private

    private func getOptions(for fragment: SSMLNode, speakerId: Int32) -> piper_synthesize_options {
        var options = piper_default_synthesize_options(synthesizer)
        let speed = fragment.lengthScale
        let lengthScale = speed > 0 ? 1.0 / speed : 1.0
        options.length_scale = max(0.1, min(Float(lengthScale), 10.0))
        options.speaker_id = speakerId
        return options
    }

    private func doSynthesize(text: String, options: piper_synthesize_options, onChunkReady: (piper_audio_chunk) -> Void) {
        let sentences = PiperSentencesExtractor.extract(from: text)
        var currentOptions = options
        
        for sentence in sentences {
            autoreleasepool {
                guard synthesizer != nil else {
                    status = .error
                    return
                }
                if status != .rendering { return }

                piper_synthesize_start(synthesizer, sentence, &currentOptions)

                var chunk = piper_audio_chunk()
                while piper_synthesize_next(synthesizer, &chunk) != PIPER_DONE {
                    if status != .rendering { return }
                    if chunk.num_samples == 0 { break }
                    onChunkReady(chunk)
                }
            }
        }
    }

    private func doSynthesizeToFile(text: String, path: String, options: piper_synthesize_options) {
        let pathURL = URL(fileURLWithPath: path)
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: pathURL) else { return }
        defer { try? fileHandle.close() }
        
        var isHeaderWritten = false
        doSynthesize(text: text, options: options) { chunk in
            if !isHeaderWritten {
                try? self.writeWavHeader(to: fileHandle, sampleRate: Int32(chunk.sample_rate))
                isHeaderWritten = true
            }
            let buffer = UnsafeBufferPointer(start: chunk.samples, count: Int(chunk.num_samples))
            fileHandle.write(Data(buffer: buffer))
        }
    }

    private func addClearBeforeStartingOperation() {
        cancel()
        operationQueue.addOperation { [weak self] in
            self?.status = .rendering
        }
    }

    private func addMarkAsCompleteOperation(_ completion: (() -> Void)?) {
        operationQueue.addOperation { [weak self] in
            self?.status = .completed
            completion?()
        }
    }

    private func writeWavHeader(to fileHandle: FileHandle, sampleRate: Int32) throws {
        let unspecCount: UInt32 = 0x7ffff000
        var data = Data()
        
        func writeString(_ string: String) {
            data.append(contentsOf: string.utf8)
        }
        func writeValue<T>(_ value: T) {
            var val = value
            withUnsafeBytes(of: &val) { data.append(contentsOf: $0) }
        }
        
        writeString("RIFF")
        writeValue(unspecCount + 36)
        writeString("WAVE")
        writeString("fmt ")
        writeValue(UInt32(16))
        writeValue(UInt16(3)) // AudioFormat = 3 (IEEE float)
        writeValue(UInt16(1)) // NumChannels = 1 (mono)
        writeValue(UInt32(sampleRate))
        writeValue(UInt32(sampleRate * 4)) // ByteRate
        writeValue(UInt16(4)) // BlockAlign
        writeValue(UInt16(32)) // BitsPerSample
        writeString("data")
        writeValue(unspecCount)
        
        fileHandle.write(data)
    }
}
