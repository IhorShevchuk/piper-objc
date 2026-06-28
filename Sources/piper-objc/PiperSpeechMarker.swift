import Foundation

@objc public enum PiperSpeechMarkerType: Int {
    public typealias RawValue = Int
    case sentence
    case word
}

@objc public class PiperSpeechMarker: NSObject {
    public let range: NSRange
    public let byteOffset: Int
    public let type: PiperSpeechMarkerType
    
    public init(range: NSRange, byteOffset: Int, type: PiperSpeechMarkerType = .sentence) {
        self.range = range
        self.byteOffset = byteOffset
        self.type = type
        super.init()
    }
    
    /// Generates an array of speech markers, including one for the sentence and estimated markers for each word.
    /// - Parameters:
    ///   - sentence: The text of the sentence.
    ///   - sentenceNSRange: The range of the sentence within the original, full text.
    ///   - startByteOffset: The starting byte offset for this sentence's audio data.
    ///   - totalBytes: The total number of bytes for the synthesized sentence audio.
    /// - Returns: An array of `PiperSpeechMarker` objects.
    public static func generateMarkers(for sentence: String, sentenceNSRange: NSRange, startByteOffset: Int, totalBytes: Int) -> [PiperSpeechMarker] {
        let words = sentence.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty, totalBytes > 0, sentenceNSRange.location != NSNotFound else {
            return [PiperSpeechMarker(range: sentenceNSRange, byteOffset: startByteOffset, type: .sentence)]
        }

        let totalCharacters = words.joined().count
        guard totalCharacters > 0 else {
            return [PiperSpeechMarker(range: sentenceNSRange, byteOffset: startByteOffset, type: .sentence)]
        }

        var markers: [PiperSpeechMarker] = []
        // Add a marker for the entire sentence first.
        markers.append(PiperSpeechMarker(range: sentenceNSRange, byteOffset: startByteOffset, type: .sentence))

        var currentByteOffset = startByteOffset
        var currentSearchIndexInSentence = sentence.startIndex

        for word in words {
            guard let wordRangeInSentence = sentence.range(of: word, options: .literal, range: currentSearchIndexInSentence..<sentence.endIndex) else {
                continue
            }
            
            let locationInSentence = sentence.distance(from: sentence.startIndex, to: wordRangeInSentence.lowerBound)
            let length = sentence.distance(from: wordRangeInSentence.lowerBound, to: wordRangeInSentence.upperBound)
            let wordNSRange = NSRange(location: sentenceNSRange.location + locationInSentence, length: length)
            let wordBytes = Int(Double(totalBytes) * (Double(word.count) / Double(totalCharacters)))
            markers.append(PiperSpeechMarker(range: wordNSRange, byteOffset: currentByteOffset, type: .word))
            currentByteOffset += wordBytes
            currentSearchIndexInSentence = wordRangeInSentence.upperBound
        }
        return markers
    }
}
