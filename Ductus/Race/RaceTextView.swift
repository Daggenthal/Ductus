import AppKit
import DuctusEngine
import SwiftUI

/// Race text as a still block of three lines. The cursor moves across the
/// text; when it reaches the next line, the block shifts up one line instantly.
/// No sliding, so it stays easy on the eyes at high speed.
struct RaceTextView: View {
    let session: TypingSession
    let lastKeyWrong: Bool
    var fontSize: CGFloat = 28
    var visibleLines = 3

    private var lineHeight: CGFloat { fontSize * 1.6 }

    var body: some View {
        GeometryReader { geometry in
            let size = fontSize
            let lines = Self.wrap(session.text, maxWidth: max(geometry.size.width, size * 10)) {
                TextMeasure.advance($0, size: size)
            }
            let current = lines.lastIndex { $0.lowerBound <= session.position } ?? 0
            // Keep one finished line above for context once past the first line.
            let first = max(0, min(current - 1, lines.count - visibleLines))
            let shown = Array(lines[first..<min(lines.count, first + visibleLines)])

            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown, id: \.lowerBound) { range in
                    Text(attributed(range))
                        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                        .frame(height: lineHeight, alignment: .leading)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .transaction { $0.animation = nil }
        }
        .frame(height: lineHeight * CGFloat(visibleLines))
    }

    private func attributed(_ range: Range<Int>) -> AttributedString {
        let text = session.text
        let position = session.position
        var result = AttributedString()
        for index in range {
            // Line breaks show as a faint return arrow.
            var piece = AttributedString(text[index] == "\n" ? "↵" : String(text[index]))
            if index < position, session.isError(at: index) {
                piece.foregroundColor = .red
                piece.backgroundColor = .red.opacity(0.15)
            } else if index < position {
                piece.foregroundColor = .secondary.opacity(0.55)
            } else if index == position {
                piece.foregroundColor = .primary
                piece.backgroundColor = lastKeyWrong ? .red.opacity(0.35) : .accentColor.opacity(0.3)
                piece.underlineStyle = .single
            } else {
                piece.foregroundColor = text[index] == "\n" ? .secondary : .primary
            }
            result += piece
        }
        return result
    }

    /// Greedy word wrap by character count, breaking after line breaks too. Each range includes the trailing
    /// space, so the cursor on a space belongs to the line it ends.
    /// Appending text only changes the last line, so earlier lines stay put.
    /// Widths are measured per character, so wide characters (Hangul jamo) wrap correctly.
    static func wrap(_ text: [Character], maxWidth: CGFloat, advance: (Character) -> CGFloat) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        var start = 0
        while start < text.count {
            // As many characters as fit, at least one.
            var end = start
            var used: CGFloat = 0
            while end < text.count {
                let width = advance(text[end])
                if used + width > maxWidth, end > start { break }
                used += width
                end += 1
            }
            if let newline = text[start..<end].firstIndex(of: "\n") {
                end = newline + 1  // a line break always ends the line
            } else if end < text.count {
                // Break after the last space within the line, if there is one.
                if let space = text[start..<end].lastIndex(of: " ") {
                    end = space + 1
                }
            }
            lines.append(start..<end)
            start = end
        }
        return lines.isEmpty ? [0..<0] : lines
    }
}
