import Foundation

@objc public class PiperSpeechMarker: NSObject {
    public let range: NSRange
    public let byteOffset: Int
    
    public init(range: NSRange, byteOffset: Int) {
        self.range = range
        self.byteOffset = byteOffset
        super.init()
    }
}
