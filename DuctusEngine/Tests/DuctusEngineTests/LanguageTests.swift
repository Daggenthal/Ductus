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
        case .arabic: "ابتثجحخدذرزسشصضطظعغفقكلمنهوي"
        case .russian: "абвгдежзийклмнопрстуфхцчшщыьэюя"
        case .ukrainian: "абвгдежзийклмнопрстуфхцчшщьюяєії"
        case .turkish: "abcçdefgğhıijklmnoöprsştuüvyz"
        case .polish: "aąbcćdeęfghijklłmnńoóprsśtuwyzźż"
        case .czech: "aábcčdďeéěfghiíjklmnňoóprřsštťuúůvyýzž"
        case .hungarian: "aábcdeéfghiíjklmnoóöőprstuúüűvz"
        case .greek: "αβγδεζηθικλμνξοπρσςτυφχψωάέήίόύώ"
        case .hebrew: "אבגדהוזחטיכךלמםנןסעפףצץקרשת"
        case .hindi: "कखगचजटडतदनपबमयरलवसहािीुेो्"
        case .persian: "ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی"
        case .japanese, .chinese: "abdeghikmnorstuyz"
        default: "abcdefghilmnopqrstuvz"
        }
        #expect(Set(core.typingUnits).isSubset(of: letters))
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
            .russian: ["c0cf250c87fec590111ee1c0f40f2e622350dbce032c280bf3f187eb0fe09d2d", "d05661c81df53f54e9973d8ccdbb0666cd91925d89b24abfad58a1073d3f0a2e", "e48cb456627e5f612b3ca655ad768546b71fc873292659d126a1d9856ce2e1a9"],
            .ukrainian: ["d05661c81df53f54e9973d8ccdbb0666cd91925d89b24abfad58a1073d3f0a2e", "33352eb03353376e9bdb10eebc1716d902ab189e2a83c056ae9db42e83d2922b", "5102c3df83bba2d2599091db9bf4b9eda3fffbc83f170c055c594b03ee5cb02f"],
            .arabic: ["c6e505c49d0e27a0ef286edd35fa69ac734320c821df54dd84b8e9d8294a952c", "dd4cf67af18cb093fcf2b094ac5f9ad28d7decd234af1f3dd21f6a6479e3920f", "250b82818401325fd51ea0685961f28e88aa83092c52164167937af434fc9949"],
            .turkish: ["c88b0f083353d3c4890998f5673e3c47bac818473e7ba4c59aff55ab501c757f", "479f97cb1849f5ea6ab0d68014e79410c6bfdf4efd8ddd042c21f22e83177b00", "f5ff667742e17d7def7e7409deca05138eede30010c173e8e98b26863bc28365"],
            .polish: ["bfadc39843ffaf07b62b26a3ce5cebba40c7d410ae368457122c89b5af15d23a", "f7d2cfe9ca172182634f40513df9916e707568106992d4bf7304e04e4cdd8aa5", "9a90952c2054bd85446aa88eb74c42420ab1d98c7d4ccc8871d732d2f1ba2ed1"],
            .czech: ["a0037dc7d14347f0e2e60d153c33e8812c673b781e72ad3c68a5ea8b2b8d30f2", "48bf115f41709ed26a6c29817e1e6f7b098ae6fde20922272fd3bcd9bb3edd11", "2016e576b39189b83f19c744587490c5964feff222eab0824d4451f6d241b347"],
            .hungarian: ["c15669d7810d9b2555fc6376557692db6c8baf82462c35bcbcbfcf053d59d0e9", "f76e5b875e053a415835d0d06d6be080601998fce946e0036a3ce87e90d4709e", "0131f813bddf1df6b7601abe7ca02bd3bb20890f3ac9eb74139ea7fcf2dfa7a8"],
            .greek: ["48ec206e1619a4fdb5912230fc96504c6f5f1d27bcbc7cc7e4970a9cbcec521d", "6cf7ce7b8c1c9e9a3c4a13d0fd46bf4ab8db41e3606dd50adf89bdd489f3e0b2", "369c311a7de62f1898509314962c2ccabaf285198bdb33be342e196b61db3f00"],
            .hebrew: ["44f5b83bb0cecee75d6b5f7ae1b20a6b655c0026e70c11d798160b1a908b85f5", "2c130c7cd105bf547e6cffe54259671e9090f9eaa4b1154f87125e7b16837be9", "be179b77dd7ea7e35877b9808cc4b90363c419df3199642c16435e52a7875fb9"],
            .hindi: ["a5364f20cf88e6db8bd9ba29e7e8e13c3422628afa025a273e5e8a3f47020dc6", "8cf60e9a2d48700efa02dd97c2bd85b7221f7d5df0bca3ac9426b70a9c999f49", "8ce21ac2c9584fef290f7e9e59f8b163d2e9f775b272e356f1cd080374c62219"],
            .persian: ["9ba38f42ac90ca08a0cc316e5cd7028522febbec8980af4e97e3dc43a6fbb209", "c060b1520a946c5a6656c8da5e18a919d670fbae6cc80e812af62993194fa3ca", "51dc1772f691e20363f9b4ccbc5e595bac1491cd3071be534c496b885a9092e7"],
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

    @Test func arabicUsesItsOwnPunctuation() {
        var rng = SeededGenerator(seed: 3)
        let words = Array(repeating: "في من أن كان هذا", count: 40).joined(separator: " ")
        let text = TextDecorator.decorate(words, style: TextStyle(punctuation: true), language: .arabic, using: &rng)
        #expect(text.contains("؟") || text.contains("،"))
        #expect(!text.contains("?") && !text.contains(","))
        #expect(PracticeLanguage.arabic.isRightToLeft && !PracticeLanguage.russian.isRightToLeft)
    }

    @Test func turkishCapitalsAndKeys() {
        var rng = SeededGenerator(seed: 1)
        let words = Array(repeating: "iyi", count: 30).joined(separator: " ")
        let text = TextDecorator.decorate(words, style: TextStyle(capitals: true), language: .turkish, using: &rng)
        #expect(text.hasPrefix("İyi"))
        #expect(Character("İ").keyLetter == "i")
        #expect(PracticeLanguage(code: "iw") == .hebrew && PracticeLanguage.hebrew.isRightToLeft)
        #expect(PracticeLanguage.greek.questionMark == ";")
    }

    @Test func devanagariIsTypedOneKeyAtATime() {
        // कि is क then the vowel sign ि; क्ष is क, virama, ष.
        #expect("कि".typingUnits == ["क", "ि"])
        #expect("क्ष".typingUnits.count == 3)
        #expect("hé".typingUnits == ["h", "é"])  // everything else stays whole
        #expect(Character("ि").isTypingLetter && Character("्").isTypingLetter && !Character("।").isTypingLetter)
        let session = TypingSession(text: "किताब")
        #expect(session.text.count == 5)
        let words = WordList([("किताब", 3)])
        #expect(words.entries.first?.letters == Set("किताब".typingUnits))
    }

    @Test func newLanguageCodes() {
        #expect(PracticeLanguage(code: "ar") == .arabic)
        #expect(PracticeLanguage(code: "ru") == .russian)
        #expect(PracticeLanguage(code: "uk") == .ukrainian)
    }
}
