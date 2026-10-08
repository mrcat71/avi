import GitKit
import SwiftUI

/// Per-row commit graph gutter. Draws vertical lanes that butt up against the
/// adjacent rows (no top/bottom padding) so continuous lanes appear as a single line.
/// Each lane is a crisp core line over a soft halo of the same color; halos go
/// down first so crossing lanes keep clean cores.
struct HistoryGraphView: View {
    let row: CommitGraphRow
    let isSelected: Bool
    let laneColors: [Int: Color]
    var laneWidth: CGFloat = 16
    /// With author pictures on, a commit's node is a ring this wide around
    /// the picture the row lays over it. Merges keep their small dot.
    var avatarDiameter: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    static let horizontalInset: CGFloat = 8
    private var horizontalInset: CGFloat {
        Self.horizontalInset
    }

    private let coreWidth: CGFloat = 1.5
    private let haloWidth: CGFloat = 6

    private struct Segment {
        let path: Path
        let color: Color
        let isEmphasized: Bool
    }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let dotLane = row.lane
            var segments: [Segment] = []

            // 1. Through-lanes: lanes that pass through this row but aren't involved in the commit.
            for lane in row.throughLanes {
                let x = xPosition(for: lane)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                segments.append(Segment(path: path, color: color(for: lane), isEmphasized: false))
            }

            // 2. Incoming segment for the commit's lane (from top to the dot).
            do {
                let x = xPosition(for: dotLane)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: midY))
                segments.append(Segment(path: path, color: color(for: dotLane), isEmphasized: isSelected))
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
                segments.append(Segment(path: path, color: color(for: mergeInLane), isEmphasized: false))
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
                segments.append(Segment(
                    path: path,
                    color: color(for: parentLane),
                    isEmphasized: isSelected && parentLane == dotLane
                ))
            }

            // Butt caps: segments meet the next row exactly, so translucent
            // halos never double up at row boundaries.
            for segment in segments {
                context.stroke(
                    segment.path,
                    with: .color(segment.color.opacity(haloOpacity)),
                    style: StrokeStyle(lineWidth: haloWidth, lineCap: .butt)
                )
            }
            for segment in segments {
                context.stroke(
                    segment.path,
                    with: .color(segment.color),
                    style: StrokeStyle(lineWidth: segment.isEmphasized ? 2 : coreWidth, lineCap: .butt)
                )
            }

            // 4. Commit dot. Merges are smaller so the commits that carry
            // changes stand out in merge-heavy histories.
            let center = CGPoint(x: xPosition(for: dotLane), y: midY)
            let dotColor = color(for: dotLane)
            let isMerge = row.commit.parentOIDs.count > 1
            if let avatarDiameter, !isMerge {
                let ring = avatarDiameter + (isSelected ? 4 : 3)
                context.fill(
                    Path(ellipseIn: circle(center, ring + 6)),
                    with: .color(dotColor.opacity(isSelected ? haloOpacity * 1.8 : haloOpacity))
                )
                context.fill(Path(ellipseIn: circle(center, ring)), with: .color(dotColor))
                return
            }
            let dotSize: CGFloat = isSelected ? 10 : (isMerge ? 5 : 7)
            let ringSize: CGFloat = isSelected ? 18 : (isMerge ? 9 : 13)
            context.fill(
                Path(ellipseIn: circle(center, ringSize)),
                with: .color(dotColor.opacity(isSelected ? haloOpacity * 1.6 : haloOpacity * 1.2))
            )
            context.fill(Path(ellipseIn: circle(center, dotSize)), with: .color(dotColor))
            if isSelected {
                context.fill(Path(ellipseIn: circle(center, 4)), with: .color(.white))
            }
        }
        .frame(width: width)
    }

    private var haloOpacity: Double {
        colorScheme == .dark ? 0.2 : 0.16
    }

    private var width: CGFloat {
        CGFloat(max(row.laneCount, 1)) * laneWidth + horizontalInset * 2
    }

    private func circle(_ center: CGPoint, _ diameter: CGFloat) -> CGRect {
        CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    private func xPosition(for lane: Int) -> CGFloat {
        Self.nodeX(lane: lane, laneWidth: laneWidth)
    }

    /// Where a lane's commits sit, from the gutter's leading edge.
    static func nodeX(lane: Int, laneWidth: CGFloat) -> CGFloat {
        horizontalInset + CGFloat(lane) * laneWidth + laneWidth / 2
    }

    private func color(for lane: Int) -> Color {
        if let stable = laneColors[lane] {
            return stable
        }
        if let identity = row.laneIdentities[lane] {
            return HistoryGraphPalette.color(for: identity)
        }
        return HistoryGraphPalette.color(forLane: lane)
    }
}
