import Foundation
import piper_utils
import piper
import libespeak_ng

@objc public protocol PiperDelegate: AnyObject {
    func piperDidReceiveSamples(_ samples: UnsafePointer<Float>, withSize count: Int)
    func piperDidGenerateMarkers(_ markers: [PiperSpeechMarker])
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
    private let modelPath: String
    private let configPath: String
    private let espeakData: String
    public var memoryThresholdBytes: UInt64? = nil
    private var totalSSMLBytesGenerated = 0

    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "\(Piper.self).main"
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

    private func recreateSynthesizer() {
        if let syn = synthesizer {
            piper_free(syn)
            synthesizer = nil
        }
        synthesizer = piper_create(modelPath, configPath, espeakData)
    }

    public convenience init?(modelPath: String, andConfigPath modelConfigPath: String) {
        self.init(modelPath: modelPath, configPath: modelConfigPath, espeakNGData: "")
    }

    public init?(modelPath: String, configPath: String, espeakNGData: String) {
        let espeakData = espeakNGData.isEmpty ? Piper.ensureEspeakLibDataInstalled() : espeakNGData
        self.modelPath = modelPath
        self.configPath = configPath
        self.espeakData = espeakData
        super.init()
        self.operationQueue.name = "\(type(of: self))Queue"
        
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
        totalSSMLBytesGenerated = 0
        operationQueue.cancelAllOperations()
        operationQueue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - Synthesis

    public func synthesize(_ text: String) {
        addClearBeforeStartingOperation()
        
        operationQueue.addOperation { [weak self] in
            guard let self = self, let syn = self.synthesizer else { return }
            let options = piper_default_synthesize_options(syn)
            // Create a dummy SSMLNode to represent the plain text.
            // This unifies the synthesis pipeline for marker generation.
            let ssmlFragment = SSMLNode(text: text, lengthScale: options.length_scale, ssmlRange: NSRange(location: 0, length: text.count))
            self.doSynthesize(text: text, options: options, ssmlFragment: ssmlFragment, onChunkReady: { chunk in
                self.delegate?.piperDidReceiveSamples(chunk.samples, withSize: Int(chunk.num_samples))
            }, onMarkers: { markers in
                if !markers.isEmpty {
                    self.delegate?.piperDidGenerateMarkers(markers)
                }
            })
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
            let pathURL = URL(fileURLWithPath: path)
            FileManager.default.createFile(atPath: path, contents: nil)
            guard let fileHandle = try? FileHandle(forWritingTo: pathURL) else { return }
            defer { try? fileHandle.close() }
            
            var isHeaderWritten = false
            self.doSynthesize(text: text, options: options, ssmlFragment: nil, onChunkReady: { chunk in
                self.writeWavChunk(to: fileHandle, chunk: chunk, isHeaderWritten: &isHeaderWritten)
            })
        }
        addMarkAsCompleteOperation(completion)
    }

    public func synthesizeSSML(_ ssml: String, speakerId: Int32) {
        addClearBeforeStartingOperation()
        
        operationQueue.addOperation { [weak self] in
            guard let self = self else { return }
            self.ssmlParser.parse(ssml: ssml) { [weak self] fragment in
                guard let self = self, self.status == .rendering else { return }
                autoreleasepool {
                    let options = self.getOptions(for: fragment, speakerId: speakerId)
                    self.doSynthesize(text: fragment.text, options: options, ssmlFragment: fragment, onChunkReady: { chunk in
                        self.delegate?.piperDidReceiveSamples(chunk.samples, withSize: Int(chunk.num_samples))
                    }, onMarkers: { markers in
                        if !markers.isEmpty {
                            self.delegate?.piperDidGenerateMarkers(markers)
                        }
                    })
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
            self.parseAndSynthesizeSSML(ssml: ssml, speakerId: speakerId) { [weak self] chunk in
                self?.writeWavChunk(to: fileHandle, chunk: chunk, isHeaderWritten: &isHeaderWritten)
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

    private func doSynthesize(text: String, options: piper_synthesize_options, ssmlFragment: SSMLNode? = nil, onChunkReady: (piper_audio_chunk) -> Void, onMarkers: (([PiperSpeechMarker]) -> Void)? = nil) {
        let sentences = PiperSentencesExtractor.extract(from: text)
        var currentOptions = options
        
        var searchStartIndex = text.startIndex

        for sentence in sentences {
            autoreleasepool {
                if let memoryThresholdBytes,
                   let memory = MemoryInfo.getMemoryUsage(), 
                   memory > memoryThresholdBytes {
                    recreateSynthesizer()
                }

                guard synthesizer != nil else {
                    status = .error
                    return
                }
                if status != .rendering { return }

                let nsRange: NSRange
                if let ssmlFragment, ssmlFragment.ssmlRange.location != NSNotFound {
                    if let sentenceRange = text.range(of: sentence, options: [], range: searchStartIndex..<text.endIndex) {
                        let locationInFragment = text.distance(from: text.startIndex, to: sentenceRange.lowerBound)
                        let length = text.distance(from: sentenceRange.lowerBound, to: sentenceRange.upperBound)
                        nsRange = NSRange(location: ssmlFragment.ssmlRange.location + locationInFragment, length: length)
                        searchStartIndex = sentenceRange.upperBound
                    } else {
                        nsRange = NSRange(location: NSNotFound, length: 0)
                    }
                } else {
                    nsRange = NSRange(location: NSNotFound, length: 0)
                }

                let sentenceStartByteOffset = self.totalSSMLBytesGenerated
                
                piper_synthesize_start(synthesizer, sentence, &currentOptions)
                
                var sentenceTotalBytes = 0
                var chunk = piper_audio_chunk()
                while piper_synthesize_next(synthesizer, &chunk) != PIPER_DONE {
                    if status != .rendering { return }
                    if chunk.num_samples == 0 { break }
                    
                    onChunkReady(chunk)
                    
                    let chunkBytes = Int(chunk.num_samples) * MemoryLayout<Float>.size
                    sentenceTotalBytes += chunkBytes
                }
                self.totalSSMLBytesGenerated += sentenceTotalBytes
                
                if nsRange.location != NSNotFound, let onMarkers {
                    let markers = PiperSpeechMarker.generateMarkers(for: sentence, sentenceNSRange: nsRange, startByteOffset: sentenceStartByteOffset, totalBytes: sentenceTotalBytes)
                    onMarkers(markers)
                }
            }
        }
    }

    private func parseAndSynthesizeSSML(ssml: String, speakerId: Int32, onChunkReady: @escaping (piper_audio_chunk) -> Void) {
        self.ssmlParser.parse(ssml: ssml) { [weak self] fragment in
            guard let self = self, self.status == .rendering else { return }
            autoreleasepool {
                let options = self.getOptions(for: fragment, speakerId: speakerId)
                self.doSynthesize(text: fragment.text, options: options, ssmlFragment: fragment, onChunkReady: onChunkReady)
            }
        }
    }
    
    private func writeWavChunk(to fileHandle: FileHandle, chunk: piper_audio_chunk, isHeaderWritten: inout Bool) {
        if !isHeaderWritten {
            try? self.writeWavHeader(to: fileHandle, sampleRate: Int32(chunk.sample_rate))
            isHeaderWritten = true
        }
        let buffer = UnsafeBufferPointer(start: chunk.samples, count: Int(chunk.num_samples))
        fileHandle.write(Data(buffer: buffer))
    }

    private func addClearBeforeStartingOperation() {
        cancel()
        status = .rendering
    }

    private func addMarkAsCompleteOperation(_ completion: (() -> Void)?) {
        operationQueue.addOperation { [weak self] in
            guard let self = self else { return }
            self.statusLock.lock()
            if self._status == .rendering {
                self._status = .completed
            }
            self.statusLock.unlock()
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
