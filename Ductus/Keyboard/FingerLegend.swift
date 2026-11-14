import SwiftUI

/// The finger colors as a small key: a colored square and the finger's name.
/// Shown in Settings and, when finger colors are on, on the floating keyboard.
struct FingerLegend: View {
    /// Smaller, for the floating keyboard's stats row.
    var compact = false

    private static let items: [(finger: KeyboardGeometry.Finger, name: LocalizedStringKey)] = [
        (.pinky, "Pinky"), (.ring, "Ring"), (.middle, "Middle"), (.index, "Index"), (.thumb, "Thumb"),
    ]

    var body: some View {
        HStack(spacing: compact ? 9 : 12) {
            ForEach(Self.items.indices, id: \.self) { index in
                let item = Self.items[index]
                HStack(spacing: compact ? 3 : 4) {
                    RoundedRectangle(cornerRadius: compact ? 2 : 3)
                        .fill(item.finger.color.opacity(compact ? 0.8 : 0.6))
                        .frame(width: compact ? 9 : 12, height: compact ? 9 : 12)
                    Text(item.name)
                        .font(compact ? .system(size: 10, weight: .medium) : .caption)
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
