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
        // Romaji has no l, q, v or x in normal words; pinyin has no v except for ü.
        let letters = Set(words.letterFrequencyOrder())
        let core = switch language {
        case .korean: "ㄱㄴㄷㄹㅁㅂㅅㅇㅈㅊㅋㅌㅍㅎㅏㅓㅗㅜㅡㅣ"
        case .japanese, .chinese: "abdeghikmnorstuyz"
        default: "abcdefghilmnopqrstuvz"
        }
        #expect(Set(core).isSubset(of: letters))
    }

    @Test func codesMatch() {
        #expect(PracticeLanguage(code: "fr") == .french)
        #expect(PracticeLanguage(code: "pt-BR") == .portuguese)
        #expect(PracticeLanguage(code: "de_CH") == .german)
        #expect(PracticeLanguage(code: "ja") == .japanese)
        #expect(PracticeLanguage(code: "zh-Hans") == .chinese)
        #expect(PracticeLanguage(code: "ko") == .korean)
        #expect(PracticeLanguage(code: "sv") == nil)
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

    @Test func romanizedWordsCarryNativeText() throws {
        let japanese = try WordList.bundled(.japanese)
        #expect(japanese.nativeForms["watashi"] == "私")
        let chinese = try WordList.bundled(.chinese)
        #expect(chinese.nativeForms["women"] == "我们")
        #expect(chinese.entries.allSatisfy { $0.word.allSatisfy { $0.isASCII && $0.isLetter } })
        // Korean is typed as 2-Set jamo: 안녕 is ㅇㅏㄴㄴㅕㅇ, compound vowels are two keys.
        let korean = try WordList.bundled(.korean)
        #expect(korean.nativeForms["ㅇㅏㄴㄴㅕㅇ"] == "안녕")
        #expect(korean.entries.allSatisfy { $0.word.unicodeScalars.allSatisfy { (0x3131...0x3163).contains($0.value) } })
        #expect(!korean.entries.contains { $0.word.contains("ㅘ") || $0.word.contains("ㄺ") })
    }

    @Test func romanizedSentencesLineUpWithNative() throws {
        for language in [PracticeLanguage.japanese, .chinese, .korean] {
            let list = try SentenceList.bundled(language)
            let aligned = list.entries.filter { $0.native != nil }
            #expect(aligned.count > list.entries.count * 9 / 10)
            for entry in aligned.prefix(50) {
                #expect(entry.native?.count == entry.text.split(separator: " ").count)
            }
        }
    }

    @Test func glossFindsTheWordUnderTheCursor() {
        let gloss = Gloss(text: "watashi ha nihongo", native: ["watashi": "私", "ha": "は", "nihongo": "日本語"])
        #expect(gloss.segments.map(\.native) == ["私", "は", "日本語"])
        #expect(gloss.segmentIndex(at: 0) == 0)
        #expect(gloss.segmentIndex(at: 7) == 0)  // the space after "watashi"
        #expect(gloss.segmentIndex(at: 8) == 1)
        #expect(gloss.segmentIndex(at: 12) == 2)
    }

    @Test func glossForSentencesKeepsOffsets() {
        let list = SentenceList(text: "kare ha.\t彼|は。\nwo ai ni.\t我|爱|你。")
        let gloss = Gloss(sentences: list.entries)
        let text = list.entries.map(\.text).joined(separator: " ")
        #expect(gloss.segments.map(\.native) == ["彼", "は。", "我", "爱", "你。"])
        for segment in gloss.segments {
            let typed = String(Array(text)[segment.range])
            #expect(!typed.contains(" "))
        }
        #expect(String(Array(text)[gloss.segments[3].range]) == "ai")
    }

    @Test func romanizedTextIsNotDecorated() {
        var rng = SeededGenerator(seed: 1)
        let text = "watashi ha nihongo wo hanasu"
        #expect(TextDecorator.decorate(text, style: TextStyle(capitals: true, punctuation: true),
                                       language: .japanese, using: &rng) == text)
    }
}
