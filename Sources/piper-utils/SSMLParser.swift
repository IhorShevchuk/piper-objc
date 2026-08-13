import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public final class SSMLParser: NSObject {
    public struct ParsedElement {
        public let text: String
        public let isSSMLTag: Bool
    }
    
    private var elements: [ParsedElement] = []
    private var currentText: String = ""
    private var insideSSMLTag = false
    
    public static func parse(_ ssmlString: String) -> [ParsedElement] {
        let parser = SSMLParser()
        return parser.parseInternal(ssmlString)
    }
    
    private func parseInternal(_ ssmlString: String) -> [ParsedElement] {
        // Simple fallback for Linux without XMLParser? Use built-in if available
        guard let data = ssmlString.data(using: .utf8) else {
            return [ParsedElement(text: ssmlString, isSSMLTag: false)]
        }
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        
        if parser.parse() {
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                elements.append(ParsedElement(text: currentText, isSSMLTag: false))
            }
            return elements
        } else {
            // Fallback: return raw string as one element
            return [ParsedElement(text: ssmlString, isSSMLTag: false)]
        }
    }
}

extension SSMLParser: XMLParserDelegate {
    public func parser(_ parser: XMLParser,
                       didStartElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String : String] = [:]) {
        // Save accumulated text before tag
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            elements.append(ParsedElement(text: currentText, isSSMLTag: false))
            currentText = ""
        }
        // Store opening tag as raw
        var tag = "<\(elementName)"
        for (key, value) in attributeDict {
            tag += " \(key)=\"\(value)\""
        }
        tag += ">"
        elements.append(ParsedElement(text: tag, isSSMLTag: true))
        insideSSMLTag = true
    }
    
    public func parser(_ parser: XMLParser,
                       didEndElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?) {
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            elements.append(ParsedElement(text: currentText, isSSMLTag: false))
            currentText = ""
        }
        elements.append(ParsedElement(text: "</\(elementName)>", isSSMLTag: true))
        insideSSMLTag = false
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
}
