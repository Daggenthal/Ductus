import DuctusEngine
import SwiftUI

/// Japanese or Chinese text over romaji or pinyin drills: the chunk you are
/// typing, large, with its neighbors faded on either side.
struct GlossBar: View {
    let gloss: Gloss
    let position: Int
    var fontSize: CGFloat = 40
    var before = 2
    var after = 3

    var body: some View {
        let segments = gloss.segments
        if let current = gloss.segmentIndex(at: position), !segments.isEmpty {
            let start = max(0, current - before)
            let end = min(segments.count, current + after + 1)
            HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.35) {
                ForEach(start..<end, id: \.self) { index in
                    Text(segments[index].native)
                        .font(.system(size: index == current ? fontSize : fontSize * 0.55))
                        .foregroundStyle(index == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .transaction { $0.animation = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(segments[current].native)
        }
    }
}
