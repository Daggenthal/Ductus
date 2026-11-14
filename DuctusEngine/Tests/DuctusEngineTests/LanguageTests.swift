import CryptoKit
import Foundation
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

    @Test func frenchSpacesBeforeTallPunctuation() {
        var rng = SeededGenerator(seed: 8)
        let words = Array(repeating: "le chat dort ici", count: 40).joined(separator: " ")
        let text = TextDecorator.decorate(words, style: TextStyle(punctuation: true), language: .french, using: &rng)
        #expect(text.contains(" ?") || text.contains(" !"))
        for mark in ["?", "!", ":", ";"] {
            for range in text.ranges(of: mark) {
                #expect(text[text.index(before: range.lowerBound)] == " ")
            }
        }
    }

    /// The corpus build filters swear words and slurs (scripts/blocklist.py).
    /// The words are kept here as SHA-256 fingerprints, so they do not appear in the repo.
    @Test func noSwearWordsInWordLists() throws {
        let banned: [PracticeLanguage: Set<String>] = [
            .english: ["2062f80093066633876b542212c496501a5e79523cc4ea9b28667dff065afd8f", "6ac3c336e4094835293a3fed8a4b5fedde1b5e2626d9838fed50693bba00af0e", "85fc17f7069acd39a5c636cd0a6530651096128da447959f5e250824857dc559", "120f6e5b4ea32f65bda68452fcfaaef06b0136e1d0e4a6f60bc3771fa0936dd6"],
            .french: ["a0f9178f3cf701a4d0017965b80302721a133943806b48b08e24e12ab73a2992", "7b18f199984c57b21bc6f65f028d25aa4f40b443f4d5e11228fff30e8edb4955"],
            .spanish: ["8fcdc6287be29b5f294cee970e039bf6c162e1b6709ab99907cf2b8444ae3ac4", "489a845537412def5431c0b0022bac0022dd00dadcb971bf375c862e5b1f0085"],
            .german: ["e9f7ea7722a6ad53f72d4d850eca2f40f886af0247858a8b38c4d451ce9001bc"],
            .italian: ["880e042d271f08cd3c456f28704702a6b0ad1c7b442f257bf40578112c8e6ffb", "66a65afbf25fc4de9327e7b1d489fe0e6ad113fbba84980c89ad83c4cfaa5b04"],
            .portuguese: ["c3423a6895e2c35db775db665ed5dd4e058f9bf8407e7dcbe008f658d79a0f2f", "c0f9c42d0879573e1fcf23e080a8e919b33d5d428678c27a1c5695f7fd0c7b81"],
            .dutch: ["341e7a8fb5984414cecd33b2418e08eb8095a95d187b27695554d320ec8b21ba", "dcff2e2c80221583fd4297745a42d1bdde5096a570b8475a04386da86c94e7d8"],
            .japanese: ["1a37b2827f8762c9485b7c6cd4ebe86067071fbfd1bbfe51fd849ffcc9e9a907", "c58a847f94dcf2d93b5c88072186977a003741cc9bcc25fe97bb09d788da6a18"],
            .chinese: ["f8ae539c6618a29cfb0a8fa662fafbc0dd48b9d2ef08c275b5c2936b488e2d99", "f6d6732bd09282844560984ced01c010e7f2e262c71d80d78f690dad83ed9e99"],
            .korean: ["32dadec2f52cc531138b43652f817e8bb3b188673042f26af15581d93ac5878a"],
        ]
        for (language, fingerprints) in banned {
            let list = try WordList.bundled(language)
            let found = list.entries.filter { entry in
                fingerprints.contains(Self.fingerprint((entry.native ?? entry.word).lowercased()))
            }
            #expect(found.isEmpty, "\(language): \(found.count) blocked word(s) in the word list")
        }
    }

    private static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
