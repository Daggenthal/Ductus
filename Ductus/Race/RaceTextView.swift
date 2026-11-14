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
            let charWidth = Self.characterWidth(fontSize)
            let perLine = max(10, Int(geometry.size.width / charWidth))
            let lines = Self.wrap(session.text, width: perLine)
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
            var piece = AttributedString(String(text[index]))
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
                piece.foregroundColor = .primary
            }
            result += piece
        }
        return result
    }

    /// Greedy word wrap by character count. Each range includes the trailing
    /// space, so the cursor on a space belongs to the line it ends.
    /// Appending text only changes the last line, so earlier lines stay put.
    static func wrap(_ text: [Character], width: Int) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        var start = 0
        while start < text.count {
            var end = min(text.count, start + width)
            if end < text.count {
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

    static func characterWidth(_ size: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return ("M" as NSString).size(withAttributes: [.font: font]).width
    }
}
