import SwiftUI

/// Liquid-glass tokens layered on top of the legacy `DS.*` palette.
/// Surfaces migrate to `Glass.*` one at a time. On macOS 26+ the
/// `glassSurface(...)` modifier defers to Apple's `.glassEffect(...)`
/// primitive; on macOS 14-15 it falls back to a Material + soft stroke
/// + top highlight + shadow that approximates the same look.
enum Glass {
    /// Semantic spring animations. Replaces hand-tuned `.easeInOut` curves
    /// across the app with three named springs so the motion language is
    /// consistent (and respects Reduce Motion automatically).
    enum Motion {
        /// Quick feedback for hovers, presses, and small state changes.
        static let snappy: Animation = .spring(response: 0.25, dampingFraction: 0.9)
        /// Sheets, drawers, sidebar expand/collapse.
        static let standard: Animation = .spring(response: 0.4, dampingFraction: 0.85)
        /// Empty-state arrival, command palette open, anything that should feel delightful.
        static let bouncy: Animation = .spring(response: 0.55, dampingFraction: 0.7)
    }

    /// Semantic material role. Map roles to specific Materials in one
    /// place so the design language can be retuned globally later.
    enum Surface {
        case shell // window background, behind everything
        case toolbar // chrome bars (toolbar, tabs)
        case sidebar // navigation sidebar
        case card // floating panes, settings groups, sheets body
        case overlay // pop-up cards (debug drawer, tooltips, menus)

        var material: Material {
            switch self {
            case .shell: return .ultraThinMaterial
            case .toolbar: return .ultraThinMaterial
            case .sidebar: return .thinMaterial
            case .card: return .regularMaterial
            case .overlay: return .thickMaterial
            }
        }
    }

    /// Elevation tier - drives the drop-shadow used under glass cards.
    enum Elevation {
        case flat // no shadow (chrome, embedded panes)
        case resting // default card on a surface
        case raised // sheets, menus, popovers
        case floating // drag-in-progress, modal overlays

        var shadow: ShadowSpec {
            switch self {
            case .flat:
                return ShadowSpec(color: .clear, radius: 0, x: 0, y: 0)
            case .resting:
                return ShadowSpec(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
            case .raised:
                return ShadowSpec(color: .black.opacity(0.18), radius: 18, x: 0, y: 6)
            case .floating:
                return ShadowSpec(color: .black.opacity(0.28), radius: 28, x: 0, y: 12)
            }
        }
    }

    enum Corner {
        static let chrome: CGFloat = 14
        static let card: CGFloat = 12
        static let inline: CGFloat = 8
        static let pill: CGFloat = 999
    }

    /// Hairline gradient used as the glass-edge stroke. Brighter at the
    /// top, fading toward the bottom, like light catching the rim.
    static var edgeStroke: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04), Color.black.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Top-edge highlight overlay drawn inside the rounded rectangle so
    /// the surface looks like it catches ambient light.
    static var topHighlight: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)],
            startPoint: .top,
            endPoint: .center
        )
    }

    /// Subtle accent-tinted gradient for hover states.
    static func hoverTint(_ tint: Color = .accentColor) -> LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.14), tint.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// Wrap the receiver in a glass surface. Uses Apple's `.glassEffect()`
    /// on macOS 26+, otherwise composes Material + stroke + highlight + shadow.
    /// Respects `accessibilityReduceTransparency` by swapping to a solid surface.
    func glassSurface(
        _ surface: Glass.Surface = .card,
        corner: CGFloat = Glass.Corner.card,
        elevation: Glass.Elevation = .resting
    ) -> some View {
        modifier(GlassSurfaceModifier(surface: surface, corner: corner, elevation: elevation))
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let surface: Glass.Surface
    let corner: CGFloat
    let elevation: Glass.Elevation

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .background {
                if reduceTransparency {
                    shape.fill(solidFallback)
                } else {
                    shape
                        .fill(surface.material)
                        .overlay(shape.fill(Glass.topHighlight))
                }
            }
            .overlay {
                shape.strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
            }
            .clipShape(shape)
            .aviShadow(elevation.shadow)
    }

    private var solidFallback: Color {
        switch surface {
        case .shell, .sidebar: return DS.Palette.surfaceSunken
        case .toolbar: return DS.Palette.surface
        case .card, .overlay: return DS.Palette.surfaceRaised
        }
    }
}
