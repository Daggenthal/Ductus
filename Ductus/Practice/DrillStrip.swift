import AppKit
import DuctusEngine
import SwiftUI

/// One line of drill text where the cursor stays in a fixed spot and the
/// text slides past it. Sits right above the keyboard so the words and the
/// keys are both in view without moving your eyes.
struct DrillStrip: View {
    let session: TypingSession
    let lastKeyWrong: Bool
    var fontSize: CGFloat = 22
    /// Where the cursor sits, as a share of the strip width.
    var anchor: CGFloat = 0.35

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let rightToLeft = TextMeasure.isRightToLeft(session.text)
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: fontSize * 1.9)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Text(attributed)
                        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                        .textDirection(rightToLeft: rightToLeft)
                        .fixedSize()
                        .offset(x: offset(width: geometry.size.width, rightToLeft: rightToLeft))
                        .frame(height: geometry.size.height)
                        .animation(.easeOut(duration: 0.09), value: session.position)
                }
            }
            .clipped()
            .mask(edgeFade)
            .textDirection(rightToLeft: false)  // placement below is in screen coordinates
    }

    /// Where the text starts, so the cursor stays put. Right-to-left text is
    /// anchored the same distance from the right edge and slides the other way.
    private func offset(width: CGFloat, rightToLeft: Bool) -> CGFloat {
        let window = visibleRange
        let typed = session.text[window.lowerBound..<min(session.position, window.upperBound)]
        guard rightToLeft else { return width * anchor - TextMeasure.width(of: typed, size: fontSize) }
        let all = session.text[window]
        return width * (1 - anchor) + TextMeasure.shapedWidth(of: typed, size: fontSize)
            - TextMeasure.shapedWidth(of: all, size: fontSize)
    }

    /// Only the text near the cursor is drawn, so long race texts stay cheap.
    private var visibleRange: Range<Int> {
        let lower = max(0, session.position - 80)
        let upper = min(session.text.count, session.position + 160)
        return lower..<upper
    }

    private var attributed: AttributedString {
        let palette = KeyboardPalette(colorScheme)
        let window = visibleRange
        let text = session.text
        let position = session.position

        var done = AttributedString()
        for i in window.lowerBound..<position {
            var piece = AttributedString(String(text[i]))
            if session.isError(at: i) {
                piece.foregroundColor = .red
                piece.backgroundColor = .red.opacity(0.15)
            } else {
                piece.foregroundColor = palette.fadedText
            }
            done += piece
        }

        var current = AttributedString(position < text.count ? String(text[position]) : "")
        current.foregroundColor = palette.text
        current.backgroundColor = lastKeyWrong ? .red.opacity(0.45) : .accentColor.opacity(0.4)

        var rest = AttributedString(position + 1 < window.upperBound ? String(text[(position + 1)..<window.upperBound]) : "")
        rest.foregroundColor = palette.text

        return done + current + rest
    }

    /// Soft fade at both ends so words do not get chopped off hard.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
