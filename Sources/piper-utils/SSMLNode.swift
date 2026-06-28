//
//  SSMLNode.swift
//  piper-objc
//
//  Created by Ihor Shevchuk on 2026-03-08.
//
import Foundation

public struct SSMLNode {
    public let text: String
    public let lengthScale: Float
    public let ssmlRange: NSRange
    public init(text: String, lengthScale: Float, ssmlRange: NSRange = NSRange(location: 0, length: 0)) {
        self.text = text
        self.lengthScale = lengthScale
        self.ssmlRange = ssmlRange
    }
}
