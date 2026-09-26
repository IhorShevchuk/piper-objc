// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Machine-readable reasons ``Piper`` creation can fail.
///
/// Raw values are stable API – do not reorder or reuse them.
@objc public enum PiperErrorCode: Int {
    /// `modelPath` was empty.
    case modelPathMissing = 1
    /// No file exists at `modelPath`.
    case modelFileMissing = 2
    /// No file exists at `configPath`.
    case configFileMissing = 3
    /// The config file exists but is empty.
    case configFileInvalid = 4
    /// The native engine refused to initialize with the given files.
    case engineCreationFailed = 5
}

/// Structured error thrown when ``Piper`` creation fails.
///
/// Bridges to `NSError` with domain ``PiperError/domain`` so Objective-C callers
/// receive the same code and path through the usual `error:` pattern.
public struct PiperError: Error, CustomNSError, CustomStringConvertible, Equatable {
    /// Domain used when bridging to `NSError`.
    public static let domain = "dev.ihor-shevchuk.piper-objc"
    /// `userInfo` key holding the file system path related to the failure, when available.
    public static let pathKey = "PiperErrorPath"

    public static var errorDomain: String { domain }

    public let code: PiperErrorCode
    public let path: String?

    public init(code: PiperErrorCode, path: String? = nil) {
        self.code = code
        self.path = path
    }

    public var errorCode: Int { code.rawValue }

    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: description]
        if let path {
            info[Self.pathKey] = path
        }
        return info
    }

    public var description: String {
        switch code {
        case .modelPathMissing:
            return "Model path is empty."
        case .modelFileMissing:
            return "Model file not found."
        case .configFileMissing:
            return "Config file not found."
        case .configFileInvalid:
            return "Config file is empty."
        case .engineCreationFailed:
            return "Engine failed to initialize."
        }
    }
}
