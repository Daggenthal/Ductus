import Testing
@testable import DuctusEngine

@Suite struct HangulTests {
    @Test func keysMatchTheCorpus() {
        #expect(Hangul.keys(of: "안") == Array("ㅇㅏㄴ"))
        #expect(Hangul.keys(of: "와") == Array("ㅇㅗㅏ"))
        #expect(Hangul.keys(of: "닭") == Array("ㄷㅏㄹㄱ"))
        #expect(Hangul.keys(of: "괜") == Array("ㄱㅗㅐㄴ"))
        #expect(Hangul.keys(of: "까") == Array("ㄲㅏ"))
        #expect(Hangul.keys(of: ".") == ["."])
    }

    @Test func composesLikeAnInputMethod() {
        #expect(Hangul.composed("한", afterKeys: 0) == "")
        #expect(Hangul.composed("한", afterKeys: 1) == "ㅎ")
        #expect(Hangul.composed("한", afterKeys: 2) == "하")
        #expect(Hangul.composed("한", afterKeys: 3) == "한")
        #expect(Hangul.composed("와", afterKeys: 2) == "오")
        #expect(Hangul.composed("와", afterKeys: 3) == "와")
        #expect(Hangul.composed("닭", afterKeys: 3) == "달")
        #expect(Hangul.composed("괜", afterKeys: 2) == "고")
        #expect(Hangul.composed("괜", afterKeys: 3) == "괘")
        #expect(Hangul.composed("?", afterKeys: 1) == "?")
    }

    @Test func blocksGroupKeysIntoSyllables() throws {
        let list = SentenceList(text: "ㅇㅏㄴㄴㅕㅇ ㄷㅏㄹㄱ.\t안녕|닭.")
        let entry = try #require(list.entries.first)
        let gloss = Gloss(sentences: [entry])
        let blocks = Hangul.blocks(text: Array(entry.text), gloss: gloss)
        #expect(String(blocks.map(\.character)) == "안녕 닭.")
        #expect(blocks.map(\.range.count) == [3, 3, 1, 4, 1])
        // Blocks cover the text exactly, in order.
        #expect(blocks.first?.range.lowerBound == 0)
        #expect(blocks.last?.range.upperBound == entry.text.count)
        for (a, b) in zip(blocks, blocks.dropFirst()) { #expect(a.range.upperBound == b.range.lowerBound) }
    }

    @Test func mismatchedWordFallsBackToKeys() {
        let text = Array("ㅇㅏㄴ")
        let gloss = Gloss(text: "ㅇㅏㄴ", native: ["ㅇㅏㄴ": "닭"])  // wrong on purpose
        #expect(Hangul.blocks(text: text, gloss: gloss).map(\.character) == text)
    }

    @Test func bundledKoreanSentencesMakeBlocks() throws {
        let list = try SentenceList.bundled(.korean)
        for entry in list.entries.prefix(200) {
            let blocks = Hangul.blocks(text: Array(entry.text), gloss: Gloss(sentences: [entry]))
            // Every Hangul syllable in the sentence shows up as one block.
            #expect(blocks.filter { Hangul.isSyllable($0.character) }.count
                    == entry.native!.joined().filter(Hangul.isSyllable).count)
        }
    }
}

@Suite struct RomajiTests {
    @Test func kanaFaithfulRomaji() {
        #expect(Romaji.from(kana: "とうきょう") == "toukyou")
        #expect(Romaji.from(kana: "きって") == "kitte")
        #expect(Romaji.from(kana: "まっち") == "macchi")
        #expect(Romaji.from(kana: "こんいん") == "konnin")
        #expect(Romaji.from(kana: "しんぶん") == "shinbun")
        #expect(Romaji.from(kana: "コーヒー") == "ko-hi-")
        #expect(Romaji.from(kana: "ぎゅうにゅう") == "gyuunyuu")
        #expect(Romaji.from(kana: "東京") == nil)
    }

    @Test func glossFromOrderedChunks() {
        let gloss = Gloss(text: "watashiha gakusei desu.", chunks: ["私は", "学生", "です。"])
        #expect(gloss.segments.map(\.native) == ["私は", "学生", "です。"])
        #expect(gloss.segments[1].range == 10..<17)
    }
}
