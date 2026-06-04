//
//  SSMLParser.swift
//  piper-objc
//
//  Created by Ihor Shevchuk on 2026-03-08.
//

import Foundation

public final class SSMLParser: NSObject {
    
    // MARK: - Context
    
    private struct SSMLContext {
        var text: String
        var rate: Float
    }
    
    // MARK: - State
    
    private var stack: [SSMLContext] = []
    private var onNode: ((SSMLNode) -> Void)?
    
    // MARK: - Public API
    
    public func parse(ssml: String, onNode: @escaping (SSMLNode) -> Void) {
        self.onNode = onNode
        defer { self.onNode = nil }
        
        guard let data = ssml.data(using: .utf8) else {
            return
        }
        
        stack = [
            SSMLContext(text: "", rate: 1.0)
        ]
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        if !parser.parse() {
            onNode(SSMLNode(text: ssml, lengthScale: 1.0))
            return
        }

        flushCurrentText()
    }
}

// MARK: - XMLParserDelegate

extension SSMLParser: XMLParserDelegate {
    
    public func parser(_ parser: XMLParser,
                       didStartElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String : String] = [:]) {
        
        flushCurrentText()

        let parent = stack.last ?? SSMLContext(text: "", rate: 1.0)
        
        var newContext = SSMLContext(
            text: "",
            rate: parent.rate
        )
        
        if elementName == "prosody",
           let rateStr = attributeDict["rate"] {
            newContext.rate = parseRate(rateStr)
        }
        stack.append(newContext)
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }
    
    public func parser(_ parser: XMLParser,
                       didEndElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?) {
        
        flushCurrentText()
        
        if stack.count > 1 {
            stack.removeLast()
        }
    }
}

// MARK: - Helpers

private extension SSMLParser {
    
    func flushCurrentText() {
        guard !stack.isEmpty else { return }
        
        var text = stack[stack.count - 1].text
        
        text = text.precomposedStringWithCanonicalMapping
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stack[stack.count - 1].text = ""
            return
        }
        
        let node = SSMLNode(
            text: text,
            lengthScale: stack[stack.count - 1].rate
        )
        
        onNode?(node)
        stack[stack.count - 1].text = ""
    }
    
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
