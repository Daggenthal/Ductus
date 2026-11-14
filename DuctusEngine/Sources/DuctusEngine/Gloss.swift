/// Native text (Japanese or Chinese) for the chunks of a romanized typing
/// text, so the app can show "日本語" while you type "nihongo".
public struct Gloss: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        /// Character offsets in the typing text.
        public let range: Range<Int>
        public let native: String
    }

    public private(set) var segments: [Segment]

    public init(segments: [Segment] = []) {
        self.segments = segments
    }

    /// Glosses each space-separated word of `text` with `native[word]`.
    /// Words without a native form get none. Trailing punctuation is ignored for lookup.
    public init(text: String, native: [String: String]) {
        segments = []
        append(text: text, offset: 0, lookup: { word in
            native[word] ?? native[String(word.filter(\.isLetter))]
        })
    }

    /// Glosses each space-separated word of `text` with the next of `chunks`, in order.
    public init(text: String, chunks: [String]) {
        segments = []
        var index = 0
        append(text: text, offset: 0, lookup: { _ in
            defer { index += 1 }
            return index < chunks.count ? chunks[index] : nil
        })
    }

    /// Glosses sentences chunk by chunk, for text made by joining them with spaces.
    public init(sentences: [SentenceList.Entry]) {
        segments = []
        var offset = 0
        for (index, sentence) in sentences.enumerated() {
            if index > 0 { offset += 1 }
            if let chunks = sentence.native {
                var chunkIndex = 0
                append(text: sentence.text, offset: offset, lookup: { _ in
                    defer { chunkIndex += 1 }
                    return chunkIndex < chunks.count ? chunks[chunkIndex] : nil
                })
            }
            offset += sentence.text.count
        }
    }

    /// Adds segments for text appended after `offset` characters (races grow their text).
    public mutating func append(text: String, offset: Int, lookup: (String) -> String?) {
        var start = offset
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let length = word.count
            if length > 0, let native = lookup(String(word)) {
                segments.append(Segment(range: start..<(start + length), native: native))
            }
            start += length + 1
        }
    }

    /// Adds another gloss whose text starts `offset` characters into this one's.
    public mutating func append(_ other: Gloss, offset: Int) {
        segments += other.segments.map {
            Segment(range: ($0.range.lowerBound + offset)..<($0.range.upperBound + offset), native: $0.native)
        }
    }

    /// Index of the segment the cursor is in or just before (on the space after a word).
    public func segmentIndex(at position: Int) -> Int? {
        if let index = segments.firstIndex(where: { $0.range.contains(position) }) { return index }
        return segments.lastIndex { $0.range.upperBound <= position }
    }
}
