import GitKit
import SwiftUI

/// Per-row commit graph gutter. Draws vertical lanes that butt up against the
/// adjacent rows (no top/bottom padding) so continuous lanes appear as a single line.
struct HistoryGraphView: View {
    let row: CommitGraphRow
    let isSelected: Bool
    let laneColors: [Int: Color]

    private let laneWidth: CGFloat = 16
    private let horizontalInset: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let dotLane = row.lane

            // 1. Through-lanes: lanes that pass through this row but aren't involved in the commit.
            for lane in row.throughLanes {
                let x = xPosition(for: lane)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(color(for: lane).opacity(0.85)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            }

            // 2. Incoming segment for the commit's lane (from top to the dot).
            do {
                let x = xPosition(for: dotLane)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: midY))
                let strokeColor = color(for: dotLane)
                let lineWidth: CGFloat = isSelected ? 2.0 : 1.5
                context.stroke(
                    path,
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }

            // 2b. Incoming curves for side-branch tails that meet this commit.
            // Each merge-in lane was alive above this row and is released here;
            // visually the tail enters the dot from above-and-to-the-side.
            for mergeInLane in row.mergeInLanes {
                let startX = xPosition(for: mergeInLane)
                let endX = xPosition(for: dotLane)
                var path = Path()
                path.move(to: CGPoint(x: startX, y: 0))
                if abs(startX - endX) < 0.5 {
                    path.addLine(to: CGPoint(x: endX, y: midY))
                } else {
                    let cp1 = CGPoint(x: startX, y: midY * 0.45)
                    let cp2 = CGPoint(x: endX, y: midY * 0.55)
                    path.addCurve(to: CGPoint(x: endX, y: midY), control1: cp1, control2: cp2)
                }
                context.stroke(
                    path,
                    with: .color(color(for: mergeInLane)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            }

            // 3. Outgoing segments for each parent lane.
            for parentLane in row.parentLanes {
                let startX = xPosition(for: dotLane)
                let endX = xPosition(for: parentLane)
                var path = Path()
                path.move(to: CGPoint(x: startX, y: midY))
                if abs(startX - endX) < 0.5 {
                    path.addLine(to: CGPoint(x: endX, y: size.height))
                } else {
                    let cp1 = CGPoint(x: startX, y: midY + (size.height - midY) * 0.55)
                    let cp2 = CGPoint(x: endX, y: midY + (size.height - midY) * 0.45)
                    path.addCurve(to: CGPoint(x: endX, y: size.height), control1: cp1, control2: cp2)
                }
                // Outgoing parent curves always use the parent lane's colour:
                // the curve is the START of that lane heading down, so it
                // reads as the new (or continuing) branch's own colour.
                let strokeColor = color(for: parentLane)
                let lineWidth: CGFloat = isSelected && parentLane == dotLane ? 2.0 : 1.5
                context.stroke(
                    path,
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }

            // 4. Commit dot.
            let dotSize: CGFloat = isSelected ? 10 : 8
            let dotRect = CGRect(
                x: xPosition(for: dotLane) - dotSize / 2,
                y: midY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(color(for: dotLane)))

            if isSelected {
                let inner: CGFloat = dotSize - 4
                let innerRect = CGRect(
                    x: xPosition(for: dotLane) - inner / 2,
                    y: midY - inner / 2,
                    width: inner,
                    height: inner
                )
                context.fill(Path(ellipseIn: innerRect), with: .color(.white))
            }
        }
        .frame(width: width)
    }

    private var width: CGFloat {
        CGFloat(max(row.laneCount, 1)) * laneWidth + horizontalInset * 2
    }

    private func xPosition(for lane: Int) -> CGFloat {
        horizontalInset + CGFloat(lane) * laneWidth + laneWidth / 2
    }

    private func color(for lane: Int) -> Color {
        if let stable = laneColors[lane] { return stable }
        if let identity = row.laneIdentities[lane] {
            return HistoryGraphPalette.color(for: identity)
        }
        return HistoryGraphPalette.color(forLane: lane)
    }
}
