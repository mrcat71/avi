import SwiftUI

/// Progress for work that takes a while, such as an AI run: a pulsing pixel
/// grid, what is happening, and how long it has been running, so a slow
/// agent never looks stuck. The clock starts when the indicator appears.
struct AviWorkingIndicator: View {
    let title: String

    @State private var startedAt = Date()
    @Environment(\.aviDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            HStack(spacing: 8) {
                PixelGridLoader(phase: reduceMotion ? nil : elapsed)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Text(Self.format(elapsed))
                    .font(DS.Font.label(density))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// "4.2s" for the first minute, then "1:05".
    static func format(_ elapsed: TimeInterval) -> String {
        if elapsed < 60 {
            return String(format: "%.1fs", (elapsed * 10).rounded(.down) / 10)
        }
        let seconds = Int(elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A 3x3 grid of squares that light up in a diagonal wave. A nil phase draws
/// it still, for Reduce Motion.
struct PixelGridLoader: View {
    let phase: TimeInterval?

    private let cell: CGFloat = 3
    private let gap: CGFloat = 1.5

    var body: some View {
        Canvas { context, _ in
            for row in 0 ..< 3 {
                for column in 0 ..< 3 {
                    let rect = CGRect(
                        x: CGFloat(column) * (cell + gap),
                        y: CGFloat(row) * (cell + gap),
                        width: cell,
                        height: cell
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 0.6),
                        with: .color(DS.Palette.accent.opacity(opacity(row: row, column: column)))
                    )
                }
            }
        }
        .frame(width: cell * 3 + gap * 2, height: cell * 3 + gap * 2)
        .accessibilityHidden(true)
    }

    private func opacity(row: Int, column: Int) -> Double {
        guard let phase else { return 0.55 }
        let wave = cos(phase * 2 * .pi / 1.2 - Double(row + column) * 0.9)
        return 0.2 + 0.8 * pow(max(0, wave), 2)
    }
}
