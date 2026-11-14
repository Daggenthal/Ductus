import Testing
@testable import DuctusEngine

@Suite struct LanguageTests {
    @Test(arguments: PracticeLanguage.allCases)
    func bundlesLoad(_ language: PracticeLanguage) throws {
        let words = try WordList.bundled(language)
        #expect(words.entries.count > 5_000)
        let sentences = try SentenceList.bundled(language)
        #expect(sentences.entries.count > 3_000)
        // The core alphabet is there. Some languages barely use k, w, x or y
        // (Italian has none of them natively), so those may be missing.
        let letters = Set(words.letterFrequencyOrder())
        #expect(Set("abcdefghilmnopqrstuvz").isSubset(of: letters))
    }

    @Test func codesMatch() {
        #expect(PracticeLanguage(code: "fr") == .french)
        #expect(PracticeLanguage(code: "pt-BR") == .portuguese)
        #expect(PracticeLanguage(code: "de_CH") == .german)
        #expect(PracticeLanguage(code: "ja") == nil)
    }

    @Test func accentedWordsKept() {
        let list = WordList([("été", 5), ("niño", 3), ("x1", 1)])
        #expect(Set(list.entries.map(\.word)) == ["été", "niño"])
        #expect(list.entries.first { $0.word == "niño" }?.letters == Set("niño"))
    }

    @Test func germanNounsKeepCase() throws {
        let list = try WordList.bundled(.german)
        #expect(list.entries.contains { $0.word == "Zeit" })
        #expect(!list.entries.contains { $0.word == "zeit" })
        // Letters are case-folded so "Zeit" matches unlocked "z e i t".
        #expect(list.words(using: Set("zeit")).contains { $0.word == "Zeit" })
        #expect(list.entries.contains { $0.word == "dass" })
        #expect(!list.entries.contains { $0.word == "daß" })
    }

    @Test func spanishInvertedMarks() {
        var rng = SeededGenerator(seed: 4)
        let text = TextDecorator.decorate(
            Array(repeating: "hola que tal", count: 30).joined(separator: " "),
            style: TextStyle(capitals: true, punctuation: true), language: .spanish, using: &rng
        )
        let questions = text.filter { $0 == "?" }.count
        #expect(questions > 0)
        #expect(text.filter { $0 == "¿" }.count == questions)
        #expect(text.filter { $0 == "¡" }.count == text.filter { $0 == "!" }.count)
    }

    @Test func germanCapitalsOnlyAtSentenceStart() {
        var rng = SeededGenerator(seed: 6)
        let words = Array(repeating: "und", count: 200).joined(separator: " ")
        let text = TextDecorator.decorate(words, style: TextStyle(capitals: true), language: .german, using: &rng)
        let capitals = text.split(separator: " ").filter { $0.first?.isUppercase == true }.count
        // Plain capitals: one per sentence of 4 to 10 words.
        #expect(capitals >= 20 && capitals <= 50)
    }

    @Test func untypeableLettersNeverUnlock() throws {
        let list = try WordList.bundled(.spanish)
        let typeable = Set("abcdefghijklmnopqrstuvwxyz")
        let trainer = Trainer(wordList: list, startingKeys: Array("aoeuidhtns"), typeable: typeable)
        #expect(!trainer.curriculum.order.contains("ñ"))
        let full = Trainer(wordList: list, startingKeys: Array("aoeuidhtns"))
        #expect(full.curriculum.order.contains("ñ"))
    }
}
