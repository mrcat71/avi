import SwiftUI

/// Cross-app design tokens. Read density via `@AppStorage("avi.density")` in views
/// that should react to changes, then translate to row height / font size.
enum DS {
    enum Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 10
        static let xl: CGFloat = 14
        static let xxl: CGFloat = 20
    }

    enum Color {
        static let divider = SwiftUI.Color.primary.opacity(0.08)
        static let rowHover = SwiftUI.Color.primary.opacity(0.05)
        static let listRowSelected = SwiftUI.Color.accentColor.opacity(0.14)
    }

    static func rowHeight(for density: Density) -> CGFloat {
        switch density {
        case .compact: return 22
        case .comfortable: return 26
        }
    }

    static func compactRowHeight(for density: Density) -> CGFloat {
        switch density {
        case .compact: return 20
        case .comfortable: return 24
        }
    }

    static func bodyFontSize(for density: Density) -> CGFloat {
        switch density {
        case .compact: return 11
        case .comfortable: return 12
        }
    }

    static func captionFontSize(for density: Density) -> CGFloat {
        switch density {
        case .compact: return 10
        case .comfortable: return 11
        }
    }
}

/// View modifier that re-reads density from UserDefaults whenever
/// `.aviDensityChanged` fires. Apply at the workspace root so descendants pick up changes.
struct DensityObserver: ViewModifier {
    @State private var density: Density = AppPreferences.density

    func body(content: Content) -> some View {
        content
            .environment(\.aviDensity, density)
            .onReceive(NotificationCenter.default.publisher(for: .aviDensityChanged)) { _ in
                density = AppPreferences.density
            }
    }
}

extension View {
    func observeDensity() -> some View {
        modifier(DensityObserver())
    }
}

/// Pre-macro EnvironmentValues key. Avoids the `@Entry` macro so the
/// fallback `./build.sh` flow works on bare Command Line Tools without
/// SwiftUIMacros plugins available.
private struct AviDensityKey: EnvironmentKey {
    static let defaultValue: Density = .comfortable
}

extension EnvironmentValues {
    var aviDensity: Density {
        get { self[AviDensityKey.self] }
        set { self[AviDensityKey.self] = newValue }
    }
}
