/// Kana to romaji the way you type it into a Japanese input method
/// (kana-faithful "wapuro" romaji): とうきょう → toukyou, きって → kitte,
/// こんいん → konnin. Same rules as `scripts/build_cjk_corpus.py`.
public enum Romaji {
    static let single: [Character: String] = [
        "ア": "a", "イ": "i", "ウ": "u", "エ": "e", "オ": "o",
        "カ": "ka", "キ": "ki", "ク": "ku", "ケ": "ke", "コ": "ko",
        "サ": "sa", "シ": "shi", "ス": "su", "セ": "se", "ソ": "so",
        "タ": "ta", "チ": "chi", "ツ": "tsu", "テ": "te", "ト": "to",
        "ナ": "na", "ニ": "ni", "ヌ": "nu", "ネ": "ne", "ノ": "no",
        "ハ": "ha", "ヒ": "hi", "フ": "fu", "ヘ": "he", "ホ": "ho",
        "マ": "ma", "ミ": "mi", "ム": "mu", "メ": "me", "モ": "mo",
        "ヤ": "ya", "ユ": "yu", "ヨ": "yo",
        "ラ": "ra", "リ": "ri", "ル": "ru", "レ": "re", "ロ": "ro",
        "ワ": "wa", "ヰ": "wi", "ヱ": "we", "ヲ": "wo",
        "ガ": "ga", "ギ": "gi", "グ": "gu", "ゲ": "ge", "ゴ": "go",
        "ザ": "za", "ジ": "ji", "ズ": "zu", "ゼ": "ze", "ゾ": "zo",
        "ダ": "da", "ヂ": "di", "ヅ": "du", "デ": "de", "ド": "do",
        "バ": "ba", "ビ": "bi", "ブ": "bu", "ベ": "be", "ボ": "bo",
        "パ": "pa", "ピ": "pi", "プ": "pu", "ペ": "pe", "ポ": "po",
        "ヴ": "vu",
        "ァ": "xa", "ィ": "xi", "ゥ": "xu", "ェ": "xe", "ォ": "xo",
        "ャ": "xya", "ュ": "xyu", "ョ": "xyo", "ヮ": "xwa", "ヵ": "xka", "ヶ": "xke",
        "ー": "-",
    ]
    static let pairs: [String: String] = [
        "キャ": "kya", "キュ": "kyu", "キョ": "kyo", "ギャ": "gya", "ギュ": "gyu", "ギョ": "gyo",
        "シャ": "sha", "シュ": "shu", "ショ": "sho", "シェ": "she",
        "ジャ": "ja", "ジュ": "ju", "ジョ": "jo", "ジェ": "je",
        "チャ": "cha", "チュ": "chu", "チョ": "cho", "チェ": "che",
        "ニャ": "nya", "ニュ": "nyu", "ニョ": "nyo", "ヒャ": "hya", "ヒュ": "hyu", "ヒョ": "hyo",
        "ビャ": "bya", "ビュ": "byu", "ビョ": "byo", "ピャ": "pya", "ピュ": "pyu", "ピョ": "pyo",
        "ミャ": "mya", "ミュ": "myu", "ミョ": "myo", "リャ": "rya", "リュ": "ryu", "リョ": "ryo",
        "ヂャ": "dya", "ヂュ": "dyu", "ヂョ": "dyo",
        "ティ": "thi", "ディ": "dhi", "デュ": "dhu", "トゥ": "twu", "ドゥ": "dwu",
        "ファ": "fa", "フィ": "fi", "フェ": "fe", "フォ": "fo", "フュ": "fyu",
        "ウィ": "wi", "ウェ": "we", "ウォ": "who", "イェ": "ye",
        "ヴァ": "va", "ヴィ": "vi", "ヴェ": "ve", "ヴォ": "vo",
        "ツァ": "tsa", "ツィ": "tsi", "ツェ": "tse", "ツォ": "tso", "クァ": "kwa", "グァ": "gwa",
    ]

    /// Hiragana to katakana; other characters unchanged.
    public static func katakana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x3041...0x3096).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0x60)! : scalar
        }))
    }

    public static func isKana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || (0x30A1...0x30FC).contains($0.value) }
    }

    /// Romaji for kana (hiragana or katakana), or `nil` if it has anything else.
    public static func from(kana text: String) -> String? {
        let kana = Array(katakana(text))
        var pieces: [String] = []
        var index = 0
        while index < kana.count {
            if index + 1 < kana.count, let pair = pairs[String(kana[index...index + 1])] {
                pieces.append(pair)
                index += 2
                continue
            }
            let character = kana[index]
            if character == "ッ" || character == "ン" {
                pieces.append(String(character))
            } else if let romaji = single[character] {
                pieces.append(romaji)
            } else {
                return nil
            }
            index += 1
        }
        // ッ doubles the next consonant; ン is "nn" before a vowel, y or n.
        var result = ""
        for (i, piece) in pieces.enumerated() {
            let next = i + 1 < pieces.count ? pieces[i + 1] : ""
            switch piece {
            case "ッ":
                if let first = next.first, !"aiueon-ッン".contains(first) { result.append(first) } else { result += "xtsu" }
            case "ン":
                if let first = next.first, "aiueoyn".contains(first) { result += "nn" } else { result += "n" }
            default:
                result += piece
            }
        }
        return result
    }
}
