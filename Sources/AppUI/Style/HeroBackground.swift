import SwiftUI

/// Subtle animated gradient used behind welcome / empty-state / hero
/// surfaces. Renders an animated `MeshGradient` on macOS 15+ and falls
/// back to a static `LinearGradient` in the same tint family on macOS 14.
struct HeroBackground: View {
    var tint: Color = .accentColor
    var intensity: Double = 0.18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .underPageBackgroundColor)
            } else if #available(macOS 15.0, *) {
                meshLayer
            } else {
                fallbackLinear
            }
        }
    }

    @available(macOS 15.0, *)
    private var meshLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let phase = sin(t * 0.25)
            let drift = Float(phase) * 0.10
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5 + drift], [0.5 + drift * 0.5, 0.5], [1.0, 0.5 - drift],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    tint.opacity(intensity * 0.6), tint.opacity(intensity * 0.2), .clear,
                    tint.opacity(intensity), Color.accentColor.opacity(intensity * 0.5), tint.opacity(intensity * 0.3),
                    .clear, tint.opacity(intensity * 0.4), tint.opacity(intensity * 0.7)
                ]
            )
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private var fallbackLinear: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            LinearGradient(
                colors: [tint.opacity(intensity), .clear, tint.opacity(intensity * 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
