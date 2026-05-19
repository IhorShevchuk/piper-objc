import Testing
@testable import piper_utils

@Suite("SSMLParser Tests")
struct SSMLParserTests {
    @Test("parses plain text")
    func testPlainText() {
        let parser = SSMLParser()
        let nodes = parser.parse(ssml: "Hello world!")
        #expect(nodes.count == 1)
        #expect(nodes[0].text == "Hello world!", "Node 0: \(nodes[0].text)")
        #expect(nodes[0].lengthScale == 1.0, "Node 0 rate: \(nodes[0].lengthScale)")
    }
    
    @Test("parses prosody rate percent correctly")
    func testProsodyRatePercent() {
        let parser = SSMLParser()
        let nodes = parser.parse(ssml: "<prosody rate=\"150%\">Fast</prosody>")
        #expect(nodes.count == 1)
        #expect(nodes[0].text == "Fast", "Node 0: \(nodes[0].text)")
        #expect(nodes[0].lengthScale == 1.5, "Node 0 rate: \(nodes[0].lengthScale)")
    }

    @Test("handles nested prosody")
    func testNestedProsody() {
        let parser = SSMLParser()
        let ssml = "<prosody rate=\"200%\">Very <prosody rate=\"50%\">slow</prosody> fast</prosody>"
        let nodes = parser.parse(ssml: ssml)
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
        let nodes = parser.parse(ssml: ssml)
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
        let n0 = parser.parse(ssml: "")
        #expect(n0.count == 1, "Empty input nodes: \(n0.count)")
        #expect(n0[0].text == "", "Empty node text: \(n0[0].text)")
        let n1 = parser.parse(ssml: "<prosody>")
        #expect(n1.count == 1, "Malformed input nodes: \(n1.count)")
        #expect(n1[0].text == "<prosody>", "Malformed node text: \(n1[0].text)")
        let n2 = parser.parse(ssml: "<prosody rate=\"abc\">text</prosody>")
        #expect(n2.count == 1)
        #expect(n2[0].text == "text", "Node text: \(n2[0].text)")
        #expect(n2[0].lengthScale == 1.0, "Node rate: \(n2[0].lengthScale)")
    }
}
