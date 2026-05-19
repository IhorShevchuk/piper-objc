//
//  SSMLNode.swift
//  piper-objc
//
//  Created by Ihor Shevchuk on 2026-03-08.
//
import Foundation

@objc public class SSMLNode: NSObject {
    @objc public let text: String
    @objc public let lengthScale: Float
    init(text: String, lengthScale: Float) {
        self.text = text
        self.lengthScale = lengthScale
        super.init()
    }
}
