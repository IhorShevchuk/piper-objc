//
//  PiperPlayer.swift
//
//
//  Created by Ihor Shevchuk on 29.05.2024.
//

import Foundation
import piper_objc

#if canImport(AVFoundation)
import AVFoundation
#endif


public class PiperPlayer {
    public struct Params {
        public let modelPath: String
        public let configPath: String
        public init(modelPath: String, configPath: String) {
            self.modelPath = modelPath
            self.configPath = configPath
        }
    }

#if canImport(AVFoundation)
    enum PlayerError: Error {
        case noPlayer
    }
#endif

    private let piper: piper_objc.Piper
#if canImport(AVFoundation)
    private var player: AVPlayer?
    private var playerContinuation: CheckedContinuation<Void, any Error>?
#endif

    public init(params: Params) {
        self.piper = piper_objc.Piper(modelPath: params.modelPath,
                                      andConfigPath: params.configPath)
#if canImport(AVFoundation)
        try? FileManager.default.createTempFolderIfNeeded(at: String.temporaryFolderPath)
#endif
    }

    deinit {
#if canImport(AVFoundation)
        try? FileManager.default.removeTempFolderIfNeeded(at: String.temporaryFolderPath)
#endif
    }

#if canImport(AVFoundation)
    public func play(text: String) async throws {
        let path = String.temporaryPath(extesnion: "wav")
        await piper.synthesize(text, toFileAtPath: path)
        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: path))
        try await playItemAsync(playerItem)
        try FileManager.default.removeItem(atPath: path)
    }

    public func stopAndCancel() async {
        await player?.pause()
        player = nil
        if let playerContinuation {
            playerContinuation.resume()
            self.playerContinuation = nil
        }
    }
#endif
}

private extension PiperPlayer {
#if canImport(AVFoundation)
    @MainActor
    func playItemAsync(_ item: AVPlayerItem) async throws {
        await stopAndCancel()
        player = AVPlayer()
        var observerEnd: Any?
        var statusObserver: NSKeyValueObservation?
        try await withCheckedThrowingContinuation { [weak self] continuation in

            let continuation = continuation as CheckedContinuation<Void, any Error>
            guard let player = self?.player else {
                continuation.resume(throwing: PlayerError.noPlayer)
                return
            }

            observerEnd = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: nil) { _ in
                continuation.resume()
            }

            statusObserver = item.observe(\.status, changeHandler: { item, _ in
                if let error = item.error {
                    continuation.resume(throwing: error)
                }
            })

            self?.playerContinuation = continuation

            player.replaceCurrentItem(with: item)
            player.play()
        }

        if let observerEnd {
            NotificationCenter.default.removeObserver(observerEnd, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }
        statusObserver?.invalidate()
        self.playerContinuation = nil
        await stopAndCancel()
    }
#endif
}
