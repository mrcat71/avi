import SwiftUI

extension DS {
    /// Canonical color palette. Use these instead of literal Color values in views.
    /// Semantic names map to system colors where possible so dark mode behaves correctly.
    enum Palette {
        // Brand / accent
        static let accent = SwiftUI.Color.accentColor
        static let accentEmphasis = SwiftUI.Color.accentColor
        static let textOnAccent = SwiftUI.Color.white

        // Semantic
        static let success = SwiftUI.Color.green
        static let warning = SwiftUI.Color.orange
        static let danger = SwiftUI.Color.red

        // Information / kinds
        static let infoBlue = SwiftUI.Color.blue
        static let infoPurple = SwiftUI.Color.purple
        static let infoOrange = SwiftUI.Color.orange
        static let infoTeal = SwiftUI.Color.teal
        static let infoPink = SwiftUI.Color.pink
        static let infoIndigo = SwiftUI.Color.indigo
        static let infoBrown = SwiftUI.Color.brown
        static let infoGreen = SwiftUI.Color.green

        // Surfaces
        static let surface = SwiftUI.Color(nsColor: .windowBackgroundColor)
        static let surfaceRaised = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let surfaceSunken = SwiftUI.Color(nsColor: .underPageBackgroundColor)

        // Text
        static let textPrimary = SwiftUI.Color.primary
        static let textSecondary = SwiftUI.Color.secondary
        static let textTertiary = SwiftUI.Color.secondary.opacity(0.6)

        // Interactive states
        static let rowHoverFill = SwiftUI.Color.primary.opacity(0.05)
        static let rowSelectedFill = SwiftUI.Color.accentColor
        static let rowSelectedSoftFill = SwiftUI.Color.accentColor.opacity(0.14)
        static let rowCurrentBranchFill = SwiftUI.Color.accentColor.opacity(0.10)

        // Lines
        static let dividerStrong = SwiftUI.Color.primary.opacity(0.10)
        static let dividerSoft = SwiftUI.Color.primary.opacity(0.06)
    }

    /// Density-aware font scale. Sizes are slightly smaller in compact mode.
    enum Font {
        static func caption(_ density: Density) -> SwiftUI.Font {
            .system(size: captionSize(density), weight: .regular)
        }

        static func captionStrong(_ density: Density) -> SwiftUI.Font {
            .system(size: captionSize(density), weight: .semibold)
        }

        static func body(_ density: Density) -> SwiftUI.Font {
            .system(size: bodySize(density), weight: .regular)
        }

        static func bodyMedium(_ density: Density) -> SwiftUI.Font {
            .system(size: bodySize(density), weight: .medium)
        }

        static func bodyBold(_ density: Density) -> SwiftUI.Font {
            .system(size: bodySize(density), weight: .semibold)
        }

        static func headline(_ density: Density) -> SwiftUI.Font {
            .system(size: headlineSize(density), weight: .semibold)
        }

        static func monoSmall(_ density: Density) -> SwiftUI.Font {
            .system(size: captionSize(density), design: .monospaced)
        }

        static func monoBody(_ density: Density) -> SwiftUI.Font {
            .system(size: bodySize(density), design: .monospaced)
        }

        static func captionSize(_ density: Density) -> CGFloat {
            density == .compact ? 10 : 11
        }

        static func bodySize(_ density: Density) -> CGFloat {
            density == .compact ? 12 : 13
        }

        static func headlineSize(_ density: Density) -> CGFloat {
            density == .compact ? 13 : 14
        }
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 10
        static let pill: CGFloat = 999
    }

    enum IconScale {
        static let xs: CGFloat = 9
        static let sm: CGFloat = 10
        static let md: CGFloat = 11
        static let lg: CGFloat = 12
        static let xl: CGFloat = 14
    }

    /// Standard row heights. Components default to `.standard`; lists in dense surfaces use `.compact`.
    enum RowHeight {
        static func standard(_ density: Density) -> CGFloat {
            density == .compact ? 22 : 26
        }

        static func compact(_ density: Density) -> CGFloat {
            density == .compact ? 20 : 24
        }

        static func panelHeader(_ density: Density) -> CGFloat {
            density == .compact ? 26 : 28
        }
    }

    enum Shadow {
        static let popover = ShadowSpec(color: .black.opacity(0.18), radius: 18, x: 0, y: 6)
        static let palette = ShadowSpec(color: .black.opacity(0.28), radius: 26, x: 0, y: 10)
    }
}

struct ShadowSpec {
    let color: SwiftUI.Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func aviShadow(_ spec: ShadowSpec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }
}
