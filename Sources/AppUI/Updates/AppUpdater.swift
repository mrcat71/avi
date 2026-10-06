import Foundation
import Observation
import os
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

/// In-app updates through Sparkle. The packaged app reads the appcast each
/// GitHub release publishes, verifies the update against the EdDSA key in its
/// Info.plist, and installs it in place. Sparkle keeps the automatic-check and
/// automatic-install choices in Avi's user defaults; this mirrors them for
/// Settings.
@MainActor
@Observable
public final class AppUpdater {
    public static let shared = AppUpdater()

    public enum State: Equatable, Sendable {
        case notStarted
        case running
        /// Why this build cannot update itself.
        case unavailable(String)
    }

    public private(set) var state: State = .notStarted
    /// False while a check or an install is under way, and when updates are off.
    public private(set) var canCheckForUpdates = false

    public var automaticallyChecksForUpdates = false {
        didSet {
            #if canImport(Sparkle)
            if let updater, updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
                updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
            #endif
        }
    }

    public var automaticallyDownloadsUpdates = false {
        didSet {
            #if canImport(Sparkle)
            if let updater, updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates {
                updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            }
            #endif
        }
    }

    #if canImport(Sparkle)
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private var updater: SPUUpdater? {
        controller?.updater
    }
    #endif

    @ObservationIgnored private let log = Logger(subsystem: "com.svinarenko.avi", category: "updates")

    private init() {}

    /// Starts Sparkle's scheduled checks. Development builds and bundles
    /// without the signing keys stay off and record why.
    public func start(bundle: Bundle = .main) {
        guard state == .notStarted else { return }
        if let problem = UpdateConfiguration.problem(for: bundle) {
            state = .unavailable(problem)
            return
        }
        #if canImport(Sparkle)
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            // Starting the updater directly, not through the controller, so a
            // configuration error lands in Settings instead of an alert at launch.
            try controller.updater.start()
        } catch {
            log.error("Sparkle did not start: \(error.localizedDescription, privacy: .public)")
            state = .unavailable("Sparkle did not start: \(error.localizedDescription)")
            return
        }
        self.controller = controller
        state = .running
        observe(controller.updater)
        #else
        state = .unavailable("This build of Avi was made without Sparkle.")
        #endif
    }

    public func checkForUpdates() {
        #if canImport(Sparkle)
        controller?.checkForUpdates(nil)
        #endif
    }

    #if canImport(Sparkle)
    /// Sparkle changes these on the main thread, also when you answer its own
    /// update alert, so Settings follows them.
    private func observe(_ updater: SPUUpdater) {
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates }
            }
        ]
    }
    #endif
}

/// Avi > Check for Updates…. Disabled while Sparkle is busy and in builds that
/// cannot update themselves.
public struct CheckForUpdatesCommand: View {
    private let updater = AppUpdater.shared

    public init() {}

    public var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
