import AppKit
import SwiftUI

#if canImport(Lottie)
import Lottie
#endif

/// SwiftUI wrapper around `LottieAnimationView`. Looks for `<name>.json` in
/// `Contents/Resources/Lottie/`, copied there by `scripts/package-app.sh`.
///
/// Resolves through `Bundle.main`, never `Bundle.module`: SwiftPM's generated
/// accessor only looks beside `Bundle.main.bundleURL` (the .app root, which
/// cannot hold signable content) and otherwise traps on the absolute build
/// directory baked in at compile time, which exists only on the build machine.
///
/// When Lottie isn't linked (e.g., the bare-CLI `./build.sh` fallback path),
/// or the named animation isn't shipped, falls back to a stock `ProgressView`
/// so the UI never blanks out.
struct LottieView: View {
    let name: String
    var loopMode: LottieLoopModeShim = .loop
    var speed: Double = 1.0
    var size: CGSize = .init(width: 96, height: 96)

    var body: some View {
        #if canImport(Lottie)
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Lottie") ??
            Bundle.main.url(forResource: name, withExtension: "json") {
            LottieRepresentable(url: url, loopMode: loopMode.lottieValue, speed: speed)
                .frame(width: size.width, height: size.height)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(width: size.width, height: size.height)
        }
        #else
        ProgressView()
            .controlSize(.large)
            .frame(width: size.width, height: size.height)
        #endif
    }
}

/// Loop mode mirror so call sites compile even when Lottie isn't linked.
enum LottieLoopModeShim {
    case playOnce
    case loop
    case autoReverse

    #if canImport(Lottie)
    var lottieValue: LottieLoopMode {
        switch self {
        case .playOnce: return .playOnce
        case .loop: return .loop
        case .autoReverse: return .autoReverse
        }
    }
    #endif
}

#if canImport(Lottie)
private struct LottieRepresentable: NSViewRepresentable {
    let url: URL
    let loopMode: LottieLoopMode
    let speed: Double

    func makeNSView(context _: Context) -> LottieAnimationView {
        let view = LottieAnimationView(filePath: url.path)
        view.loopMode = loopMode
        view.animationSpeed = CGFloat(speed)
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        view.play()
        return view
    }

    func updateNSView(_ nsView: LottieAnimationView, context _: Context) {
        nsView.loopMode = loopMode
        nsView.animationSpeed = CGFloat(speed)
        if !nsView.isAnimationPlaying {
            nsView.play()
        }
    }
}
#endif
