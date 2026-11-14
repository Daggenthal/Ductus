import AppKit
import DuctusEngine
import SwiftUI

/// Korean drill text as real syllable blocks (안녕), while typing still goes
/// key by key (ㅇ ㅏ ㄴ ...). The block you are on builds up as you type, like
/// an input method (ㅎ → 하 → 한), over a faint copy of the target. Finished
/// blocks stay colored, or red if a key in them was missed.
struct HangulText: View {
    enum Style {
        /// Every line, wrapped (practice).
        case paragraph
        /// A still window of lines; the current line is second once past the first (races).
        case window(lines: Int)
        /// One line sliding past a fixed cursor spot (floating keyboard).
        case strip(anchor: CGFloat)
    }

    let session: TypingSession
    let gloss: Gloss
    let lastKeyWrong: Bool
    var fontSize: CGFloat = 28
    var style: Style = .paragraph

    private var lineHeight: CGFloat { fontSize * 1.6 }

    var body: some View {
        let blocks = Hangul.blocks(text: session.text, gloss: gloss)
        let current = blocks.firstIndex { $0.range.contains(session.position) } ?? blocks.count
        switch style {
        case .strip(let anchor):
            strip(blocks, current: current, anchor: anchor)
        case .paragraph:
            GeometryReader { geometry in
                lines(blocks, current: current, width: geometry.size.width, visible: nil)
            }
            .frame(height: lineHeight * CGFloat(max(1, lineCount(blocks))))
        case .window(let count):
            GeometryReader { geometry in
                lines(blocks, current: current, width: geometry.size.width, visible: count)
            }
            .frame(height: lineHeight * CGFloat(count))
        }
    }

    // MARK: - Layout

    private func font() -> NSFont { NSFont.systemFont(ofSize: fontSize) }

    private func width(_ block: Hangul.Block) -> CGFloat {
        (String(block.character) as NSString).size(withAttributes: [.font: font()]).width
    }

    /// Greedy wrap by block width, breaking after spaces.
    private func wrap(_ blocks: [Hangul.Block], width maxWidth: CGFloat) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        var start = 0
        while start < blocks.count {
            var end = start
            var used: CGFloat = 0
            var lastSpace: Int?
            while end < blocks.count {
                let w = width(blocks[end])
                if used + w > maxWidth, end > start { break }
                if blocks[end].character == " " { lastSpace = end }
                used += w
                end += 1
            }
            if end < blocks.count, let lastSpace, lastSpace >= start { end = lastSpace + 1 }
            lines.append(start..<end)
            start = end
        }
        return lines
    }

    @State private var measuredWidth: CGFloat = 600

    private func lineCount(_ blocks: [Hangul.Block]) -> Int {
        wrap(blocks, width: measuredWidth).count
    }

    private func lines(_ blocks: [Hangul.Block], current: Int, width: CGFloat, visible: Int?) -> some View {
        let all = wrap(blocks, width: max(width, fontSize * 6))
        let currentLine = all.lastIndex { $0.lowerBound <= current } ?? 0
        let shown: ArraySlice<Range<Int>>
        if let visible {
            let first = max(0, min(currentLine - 1, all.count - visible))
            shown = all[first..<min(all.count, first + visible)]
        } else {
            shown = all[...]
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown), id: \.lowerBound) { line in
                HStack(spacing: 0) {
                    ForEach(line, id: \.self) { index in
                        BlockView(block: blocks[index], state: state(of: index, blocks[index], current: current),
                                  fontSize: fontSize, lastKeyWrong: lastKeyWrong)
                    }
                }
                .frame(height: lineHeight, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transaction { $0.animation = nil }
        .onAppear { measuredWidth = width }
        .onChange(of: width) { _, new in measuredWidth = new }
    }

    private func strip(_ blocks: [Hangul.Block], current: Int, anchor: CGFloat) -> some View {
        let lower = max(0, current - 30)
        let upper = min(blocks.count, current + 60)
        let before = blocks[lower..<min(current, upper)].reduce(0) { $0 + width($1) }
        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: fontSize * 1.9)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(lower..<upper, id: \.self) { index in
                            BlockView(block: blocks[index], state: state(of: index, blocks[index], current: current),
                                      fontSize: fontSize, lastKeyWrong: lastKeyWrong)
                        }
                    }
                    .fixedSize()
                    .offset(x: geometry.size.width * anchor - before)
                    .frame(height: geometry.size.height)
                    .animation(.easeOut(duration: 0.09), value: current)
                }
            }
            .clipped()
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing))
    }

    // MARK: - State

    private func state(of index: Int, _ block: Hangul.Block, current: Int) -> BlockView.State {
        let position = session.position
        let hasError = block.range.lowerBound < position
            && (block.range.lowerBound..<min(position, block.range.upperBound)).contains { session.isError(at: $0) }
        if index < current { return hasError ? .missed : .done }
        if index > current { return .pending }
        if hasError { return .current(partial: "", missed: true) }
        return .current(partial: Hangul.composed(block.character, afterKeys: position - block.range.lowerBound),
                        missed: false)
    }
}

private struct BlockView: View {
    enum State: Equatable {
        case done, missed, pending
        case current(partial: String, missed: Bool)
    }

    let block: Hangul.Block
    let state: State
    let fontSize: CGFloat
    let lastKeyWrong: Bool

    var body: some View {
        let text = String(block.character)
        ZStack {
            Text(text)
                .foregroundStyle(targetStyle)
            if case .current(let partial, _) = state, !partial.isEmpty {
                Text(partial)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: fontSize))
        .fixedSize()
        .padding(.vertical, fontSize * 0.08)
        .background(background, in: RoundedRectangle(cornerRadius: fontSize * 0.15))
    }

    private var targetStyle: AnyShapeStyle {
        switch state {
        case .done: AnyShapeStyle(Color.accentColor.opacity(0.75))
        case .missed: AnyShapeStyle(Color.red)
        case .pending: AnyShapeStyle(.primary)
        case .current(let partial, let missed):
            missed ? AnyShapeStyle(Color.red) : partial.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
        }
    }

    private var background: Color {
        switch state {
        case .missed: .red.opacity(0.15)
        case .current(_, let missed): (lastKeyWrong || missed) ? .red.opacity(0.35) : .accentColor.opacity(0.25)
        default: .clear
        }
    }
}
