import Testing
@testable import DuctusEngine

@Suite struct CustomTextTests {
    @Test func normalizesTypography() {
        let cleaned = CustomText.clean("“Hello”—it’s\u{00A0}fine… ok")
        #expect(cleaned.text == "\"Hello\"-it's fine... ok")
        #expect(cleaned.dropped == 0)
    }

    @Test func joinsWhitespaceWithoutLineBreaks() {
        let cleaned = CustomText.clean("  one\n\ntwo\tthree   four \n")
        #expect(cleaned.text == "one two three four")
    }

    @Test func keepsLinesAndDropsIndentation() {
        let code = "func a() {\n    let x = 1\n\n\n    return x\n}\n\n"
        let cleaned = CustomText.clean(code, keepLineBreaks: true)
        #expect(cleaned.text == "func a() {\nlet x = 1\n\nreturn x\n}")
    }

    @Test func dropsWhatTheLayoutCannotType() {
        let cleaned = CustomText.clean("café 😀 €5", canType: { $0.isASCII })
        #expect(cleaned.text == "caf 5")
        #expect(cleaned.dropped == 3)
    }

    @Test func partsBreakAtSentences() {
        let sentence = "This is a sentence of some length. "
        let text = String(repeating: sentence, count: 30).trimmingCharacters(in: .whitespaces)
        let parts = CustomText.parts(of: text, target: 300)
        #expect(parts.count > 3)
        for part in parts.dropLast() {
            #expect(part.hasSuffix("."))
            #expect(part.count <= 300 && part.count >= 150)
        }
        // Nothing is lost except the spaces between parts.
        #expect(parts.joined(separator: " ") == text)
    }

    @Test func partsPreferLineEnds() {
        let lines = (1...40).map { "line number \($0) here" }.joined(separator: "\n")
        let parts = CustomText.parts(of: lines, target: 200)
        #expect(parts.allSatisfy { $0.hasSuffix("here") })
        #expect(parts.joined(separator: "\n") == lines)
    }

    @Test func longWordStillSplits() {
        let parts = CustomText.parts(of: String(repeating: "x", count: 700), target: 300)
        #expect(parts.map(\.count) == [300, 300, 100])
    }

    @Test func titles() {
        #expect(CustomText.title(for: "Short one\nmore") == "Short one")
        #expect(CustomText.title(for: "The quick brown fox jumps over the lazy dog and keeps going") == "The quick brown fox jumps over the lazy…")
    }
}
