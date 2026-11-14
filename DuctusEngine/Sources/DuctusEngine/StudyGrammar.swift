import Foundation

/// The HSK grammar points for one level (revised HSK 3.0 syllabus), each with
/// example sentences from Tatoeba that were checked by hand (see CORPUS.md).
public struct GrammarSet: Sendable {
    public struct Example: Sendable, Hashable, Identifiable {
        /// Toneless pinyin to type, with the sentence's punctuation keys.
        public let typed: String
        /// The sentence in characters, one chunk per word.
        public let chunks: [String]
        /// Pinyin with tone marks, one per chunk.
        public let tones: [String]
        public let english: String
        /// Tatoeba sentence ID.
        public let id: String

        public var text: String { chunks.joined() }
        public var pinyin: String { tones.joined(separator: " ") }
    }

    public struct Point: Sendable, Hashable, Identifiable {
        /// Number in the syllabus ("2.2.1").
        public let section: String
        /// The syllabus title in Chinese ("能愿动词").
        public let title: String
        /// The words or patterns it covers ("会、能").
        public let items: String
        /// A short English name ("Modal verbs").
        public let english: String
        public var examples: [Example]
        public var id: String { "\(section)|\(items)" }
    }

    public let id: String
    public let points: [Point]
    /// Every point with examples has had them checked by hand.
    public var hasExamples: Bool { points.contains { !$0.examples.isEmpty } }

    public init(id: String, tsv: String) {
        self.id = id
        var points: [Point] = []
        for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if columns.first == "@" {
                guard columns.count >= 4 else { continue }
                points.append(Point(section: columns[1], title: columns[2], items: columns[3],
                                    english: columns.count > 4 ? columns[4] : "", examples: []))
            } else if columns.count >= 5, !points.isEmpty {
                let example = Example(typed: columns[0], chunks: columns[1].split(separator: "|").map(String.init),
                                      tones: columns[2].split(separator: "|").map(String.init),
                                      english: columns[3], id: columns[4])
                points[points.count - 1].examples.append(example)
            }
        }
        self.points = points
    }

    /// Grammar for a word set ID ("hsk1"), if there is any.
    public static func bundled(_ setID: String) -> GrammarSet? {
        guard let url = Bundle.module.url(forResource: "study-grammar-\(setID)", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return GrammarSet(id: setID, tsv: text)
    }

    /// Authors of the grammar example sentences and their translations, most first.
    public static func authors() -> [(author: String, sentences: Int)] {
        guard let url = Bundle.module.url(forResource: "study-grammar-credits", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var counts: [String: Int] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t")
            if columns.count == 2 { counts[String(columns[1]), default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }
            .sorted { $0.sentences != $1.sentences ? $0.sentences > $1.sentences : $0.author < $1.author }
    }
}
