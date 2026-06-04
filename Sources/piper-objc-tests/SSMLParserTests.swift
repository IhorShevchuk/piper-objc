import Testing
@testable import piper_utils

@Suite("SSMLParser Tests")
struct SSMLParserTests {
    @Test("parses plain text")
    func testPlainText() {
        let parser = SSMLParser()
        var nodes: [SSMLNode] = []
        parser.parse(ssml: "Hello world!") { nodes.append($0) }
        #expect(nodes.count == 1)
        #expect(nodes[0].text == "Hello world!", "Node 0: \(nodes[0].text)")
        #expect(nodes[0].lengthScale == 1.0, "Node 0 rate: \(nodes[0].lengthScale)")
    }
    
    @Test("parses prosody rate percent correctly")
    func testProsodyRatePercent() {
        let parser = SSMLParser()
        var nodes: [SSMLNode] = []
        parser.parse(ssml: "<prosody rate=\"150%\">Fast</prosody>") { nodes.append($0) }
        #expect(nodes.count == 1)
        #expect(nodes[0].text == "Fast", "Node 0: \(nodes[0].text)")
        #expect(nodes[0].lengthScale == 1.5, "Node 0 rate: \(nodes[0].lengthScale)")
    }

    @Test("handles nested prosody")
    func testNestedProsody() {
        let parser = SSMLParser()
        let ssml = "<prosody rate=\"200%\">Very <prosody rate=\"50%\">slow</prosody> fast</prosody>"
        var nodes: [SSMLNode] = []
        parser.parse(ssml: ssml) { nodes.append($0) }
        #expect(nodes.count == 3, "Node count: \(nodes.count)")
        // Node 0: "Very", rate=2.0
        #expect(nodes[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == "Very", "Node 0: \(nodes[0].text)")
        #expect(abs(nodes[0].lengthScale - 2.0) < 0.01, "Node 0 rate: \(nodes[0].lengthScale)")
        // Node 1: "slow", rate=0.5
        #expect(nodes[1].text.trimmingCharacters(in: .whitespacesAndNewlines) == "slow", "Node 1: \(nodes[1].text)")
        #expect(abs(nodes[1].lengthScale - 0.5) < 0.01, "Node 1 rate: \(nodes[1].lengthScale)")
        // Node 2: " fast", rate=2.0
        #expect(nodes[2].text.trimmingCharacters(in: .whitespacesAndNewlines) == "fast", "Node 2: \(nodes[2].text)")
        #expect(abs(nodes[2].lengthScale - 2.0) < 0.01, "Node 2 rate: \(nodes[2].lengthScale)")
    }
    
    @Test("handles French prosody inside speak tag")
    func testNestedFrenchProsody() {
        let parser = SSMLParser()
        let ssml = "<speak>L’élève <prosody rate=\"50%\">écoute</prosody> bien.</speak>"
        var nodes: [SSMLNode] = []
        parser.parse(ssml: ssml) { nodes.append($0) }
        #expect(nodes.count == 3, "Node count: \(nodes.count)")
        // Node 0: "L’élève", rate=1.0
        #expect(nodes[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == "L’élève", "Node 0: \(nodes[0].text)")
        #expect(abs(nodes[0].lengthScale - 1.0) < 0.01, "Node 0 rate: \(nodes[0].lengthScale)")
        // Node 1: "écoute", rate=0.5
        #expect(nodes[1].text.trimmingCharacters(in: .whitespacesAndNewlines) == "écoute", "Node 1: \(nodes[1].text)")
        #expect(abs(nodes[1].lengthScale - 0.5) < 0.01, "Node 1 rate: \(nodes[1].lengthScale)")
        // Node 2: " bien.", rate=1.0
        #expect(nodes[2].text.trimmingCharacters(in: .whitespacesAndNewlines) == "bien.", "Node 2: \(nodes[2].text)")
        #expect(abs(nodes[2].lengthScale - 1.0) < 0.01, "Node 2 rate: \(nodes[2].lengthScale)")
    }

    @Test("returns empty for malformed or empty input")
    func testMalformedAndEmpty() {
        let parser = SSMLParser()
        var n0: [SSMLNode] = []
        parser.parse(ssml: "") { n0.append($0) }
        #expect(n0.count == 1, "Empty input nodes: \(n0.count)")
        #expect(n0[0].text == "", "Empty node text: \(n0[0].text)")
        var n1: [SSMLNode] = []
        parser.parse(ssml: "<prosody>") { n1.append($0) }
        #expect(n1.count == 1, "Malformed input nodes: \(n1.count)")
        #expect(n1[0].text == "<prosody>", "Malformed node text: \(n1[0].text)")
        var n2: [SSMLNode] = []
        parser.parse(ssml: "<prosody rate=\"abc\">text</prosody>") { n2.append($0) }
        #expect(n2.count == 1)
        #expect(n2[0].text == "text", "Node text: \(n2[0].text)")
        #expect(n2[0].lengthScale == 1.0, "Node rate: \(n2[0].lengthScale)")
    }

    @Test("handles XML entities correctly")
    func testXMLEntities() {
        let parser = SSMLParser()
        // &amp; -> &, &lt; -> <, &quot; -> "
        let ssml = "<speak>Fish &amp; Chips are &lt; $10 &quot;Special&quot;</speak>"
        var nodes: [SSMLNode] = []
        parser.parse(ssml: ssml) { nodes.append($0) }
        
        #expect(nodes.count == 1)
        #expect(nodes[0].text == "Fish & Chips are < $10 \"Special\"")
    }

    @Test("ignores XML comments")
    func testXMLComments() {
        let parser = SSMLParser()
        let ssml = "<speak>Visible <!-- This is a comment --> text</speak>"
        var nodes: [SSMLNode] = []
        parser.parse(ssml: ssml) { nodes.append($0) }
        
        #expect(nodes.count == 1)
        // The parser usually leaves the whitespace where the comment was
        #expect(nodes[0].text.contains("Visible"))
        #expect(nodes[0].text.contains("text"))
        #expect(!nodes[0].text.contains("comment"))
    }

    @Test("handles multiple speed changes in sequence")
    func testSequentialProsody() {
        let parser = SSMLParser()
        let ssml = "<speak><prosody rate='50%'>Slow</prosody><prosody rate='200%'>Fast</prosody></speak>"
        var nodes: [SSMLNode] = []
        parser.parse(ssml: ssml) { nodes.append($0) }
        
        #expect(nodes.count == 2)
        #expect(nodes[0].lengthScale == 0.5)
        #expect(nodes[1].lengthScale == 2.0)
    }

    @Test("ignores unsupported tags but preserves inner text")
    func testUnsupportedTags() {
        let parser = SSMLParser()
        let ssml = "<speak><voice name='en_US'>Hello <emphasis>world</emphasis></voice></speak>"
        var nodes: [SSMLNode] = []
        parser.parse(ssml: ssml) { nodes.append($0) }
        
        // Current implementation flushes on every tag start/end.
        // "Hello " is one node, "world" is another.
        #expect(nodes.count >= 2)
        let joined = nodes.map { $0.text }.joined()
        #expect(joined.contains("Hello"))
        #expect(joined.contains("world"))
    }

    @Test("handles text outside of speak tags")
    func testTextOutsideSpeakTag() {
        let parser = SSMLParser()
        let ssml = "Before <speak>Inside</speak> After"
        var nodes: [SSMLNode] = []
        parser.parse(ssml: ssml) { nodes.append($0) }
        
        let allText = nodes.map { $0.text }.joined(separator: " ")
        #expect(allText.contains("Before"))
        #expect(allText.contains("Inside"))
        #expect(allText.contains("After"))
    }

    @Test("parses attribute with single quotes and extra spaces")
    func testAttributeFormattingVariations() {
        let parser = SSMLParser()
        let ssml = "<prosody   rate = ' 50% ' >Slow</prosody>"
        var nodes: [SSMLNode] = []
        parser.parse(ssml: ssml) { nodes.append($0) }
        
        #expect(nodes.count == 1)
        #expect(nodes[0].lengthScale == 0.5)
        #expect(nodes[0].text == "Slow")
    }
}
