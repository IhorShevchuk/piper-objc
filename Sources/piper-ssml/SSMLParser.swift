//
//  SSMLParser.swift
//  piper-objc
//
//  Created by Ihor Shevchuk on 2026-03-08.
//

import Foundation

public final class SSMLParser: NSObject {
    
    var ssmlNodes: [SSMLNode]
    var currentRate: Float

    public override init() {
        currentRate = 1.0
        ssmlNodes = []
        super.init()
    }
    
    @objc public func parse(ssml: String) -> [SSMLNode] {
        ssmlNodes.removeAll()
        guard let data = ssml.data(using: .utf8) else {
            return []
        }
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        if !parser.parse() {
            return []
        }
        
        return ssmlNodes
    }
}

extension SSMLParser: XMLParserDelegate {
    public func parser(_ parser: XMLParser,
                       didStartElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String : String] = [:]) {
        if elementName == "prosody" {
            if let rateStr = attributeDict["rate"] {
                currentRate = parseRate(rateStr)
            }
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmed.isEmpty {
            let node = SSMLNode(text: trimmed, lengthScale: currentRate)
            ssmlNodes.append(node)
        }
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "prosody" {
            currentRate = 1.0 
        }
    }
    
    // MARK Helper
    
    func parseRate(_ value: String) -> Float {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%") {
            let rateStr = trimmed.replacingOccurrences(of: "%", with: "")
            if let rate = Double(rateStr) {
                return Float(rate / 100.0)
            }
        }
        return 1.0
    }
}
