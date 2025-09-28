//
//  main.swift
//  piper-objc
//
//  Created by Ihor Shevchuk on 9/28/25.
//

import Foundation
import piper_player

@main
struct PiperSample {
    
    enum Error: Swift.Error {
        case noModelPath
        case noConfigPath
        case unknown
    }
    
    static var moduleBunlde: Bundle? {
        let bunldePath = "\(Bundle.main.bundlePath)/piper-objc_piper-sample.bundle"
        return Bundle(path: bunldePath)
    }
    
    static var modelPath: String? {
        return moduleBunlde?.path(forResource: "model", ofType: "onnx")
    }
    
    static var configPath: String? {
        return moduleBunlde?.path(forResource: "model.onnx", ofType: "json")
    }
    
    static var espeakNGData: String? {
        return moduleBunlde?.path(forResource: "espeak-ng-data", ofType: "")
    }
    
    static func main() throws {
        guard let modelPath else {
            throw Error.noModelPath
        }
        guard let configPath else {
            throw Error.noConfigPath
        }
        
        let params = PiperPlayer.Params(modelPath: modelPath,
                                        configPath: configPath,
                                        espeakNGData: espeakNGData)
        let player = try PiperPlayer(params: params)
        
        Task {
            do {
                try await player.play(text: "Привіт. Мене звуть Лада.")
            } catch {
                print("Catched an error: \(error)")
            }
        }
        RunLoop.main.run()
    }
}
