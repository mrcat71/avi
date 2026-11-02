#if canImport(Sparkle)
import AppKit
import os
import Sparkle

/// Sparkle's user interface for Avi. Every step of an update, from the check
/// to the relaunch, is the update notice at the top of the window, in place
/// of Sparkle's own windows. The driver keeps Sparkle's pending reply and
/// answers it with the button you click.
@MainActor
final class UpdateNoticeDriver: NSObject, SPUUserDriver {
    /// Starts a new check, for Try Again.
    var checkAgain: @MainActor () -> Void = {}

    private let center: AviNoticeCenter
    private let currentVersion: String
    private let log = Logger(subsystem: "com.svinarenko.avi", category: "updates")

    private var phase: UpdatePhase? {
        didSet { render() }
    }

    private var offer: UpdateOffer?
    private var expectedLength: UInt64?
    private var receivedLength: UInt64 = 0
    /// You already chose to install; the relaunch needs no second click.
    private var relaunchWhenReady = false

    // Sparkle's callbacks that wait for an answer. Each is called once.
    private var permissionReply: ((SUUpdatePermissionResponse) -> Void)?
    private var choiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var cancellation: (() -> Void)?
    private var acknowledgement: (() -> Void)?
    private var retryTermination: (() -> Void)?

    init(center: AviNoticeCenter = .shared, currentVersion: String) {
        self.center = center
        self.currentVersion = currentVersion
    }

    // MARK: - SPUUserDriver

    func show(_: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        permissionReply = reply
        phase = .permission
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        phase = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        relaunchWhenReady = false
        let offer = Self.offer(from: appcastItem, state: state, currentVersion: currentVersion)
        self.offer = offer
        choiceReply = reply
        phase = .available(offer)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard var offer, let text = String(data: downloadData.data, encoding: .utf8) else { return }
        let type = downloadData.mimeType?.lowercased() ?? ""
        offer.notes = text
        offer.notesFormat = type.contains("html") ? .html : (type.contains("markdown") ? .markdown : .plainText)
        self.offer = offer
        if case .available = phase {
            phase = .available(offer)
        }
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        log.error("Release notes did not download: \(error.localizedDescription, privacy: .public)")
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        cancellation = nil
        self.acknowledgement = acknowledgement
        let nsError = error as NSError
        let reason = (nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)
            .flatMap { SPUNoUpdateFoundReason(rawValue: $0.int32Value) } ?? .unknown
        switch reason {
        case .onLatestVersion, .onNewerThanLatestVersion, .unknown:
            phase = .upToDate(currentVersion: currentVersion)
        default:
            phase = .unavailable(title: nsError.localizedDescription, message: nsError.localizedRecoverySuggestion)
        }
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        cancellation = nil
        choiceReply = nil
        self.acknowledgement = acknowledgement
        let nsError = error as NSError
        log.error("Update failed: \(nsError.localizedDescription, privacy: .public)")
        let message = [nsError.localizedDescription, nsError.localizedRecoverySuggestion]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        phase = .failed(message: message)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        receivedLength = 0
        expectedLength = nil
        phase = .downloading(offer, received: 0, expected: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength > 0 ? expectedContentLength : nil
        phase = .downloading(offer, received: receivedLength, expected: expectedLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        phase = .downloading(offer, received: receivedLength, expected: expectedLength)
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        phase = .preparing(offer, progress: nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        phase = .preparing(offer, progress: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if relaunchWhenReady {
            relaunchWhenReady = false
            phase = .installing(offer, canRetry: false)
            reply(.install)
        } else {
            choiceReply = reply
            phase = .ready(offer)
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
        phase = .installing(offer, canRetry: !applicationTerminated)
    }

    func showUpdateInstalledAndRelaunched(_: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        self.acknowledgement = nil
        phase = .installed
    }

    func showUpdateInFocus() {
        NSApp.activate(ignoringOtherApps: true)
        center.callAttention(to: UpdateNotice.id)
    }

    func dismissUpdateInstallation() {
        permissionReply = nil
        choiceReply = nil
        cancellation = nil
        retryTermination = nil
        relaunchWhenReady = false
        offer = nil
        // Keep a result you have not read yet; its close button acknowledges it.
        if acknowledgement == nil {
            phase = nil
        }
    }

    // MARK: - Buttons

    private var handlers: UpdateNoticeHandlers {
        UpdateNoticeHandlers(
            install: { [weak self] in self?.reply(.install) },
            later: { [weak self] in self?.reply(.later) },
            skip: { [weak self] in self?.reply(.skip) },
            cancel: { [weak self] in self?.cancel() },
            acknowledge: { [weak self] in self?.acknowledge() },
            allowAutomaticChecks: { [weak self] allow in self?.answerPermission(allow) },
            retry: { [weak self] in
                self?.acknowledge()
                self?.checkAgain()
            },
            retryQuit: { [weak self] in self?.retryTermination?() },
            openURL: { url in NSWorkspace.shared.open(url) }
        )
    }

    private func reply(_ choice: UpdateChoice) {
        guard let reply = choiceReply else { return }
        choiceReply = nil
        let next = UpdateFlow.after(choice, in: phase, offer: offer)
        relaunchWhenReady = next.relaunchWhenReady
        phase = next.phase
        switch choice {
        case .install: reply(.install)
        case .later: reply(.dismiss)
        case .skip: reply(.skip)
        }
    }

    private func cancel() {
        let cancellation = cancellation
        self.cancellation = nil
        phase = nil
        cancellation?()
    }

    private func acknowledge() {
        let acknowledgement = acknowledgement
        self.acknowledgement = nil
        phase = nil
        acknowledgement?()
    }

    private func answerPermission(_ allow: Bool) {
        guard let reply = permissionReply else { return }
        permissionReply = nil
        phase = nil
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: allow, sendSystemProfile: false))
    }

    private func render() {
        if let phase {
            center.show(UpdateNotice.make(phase, handlers: handlers))
        } else {
            center.dismiss(id: UpdateNotice.id)
        }
    }

    // MARK: - Feed items

    private static func offer(from item: SUAppcastItem, state: SPUUserUpdateState, currentVersion: String) -> UpdateOffer {
        let format: UpdateOffer.NotesFormat
        switch item.itemDescriptionFormat?.lowercased() {
        case "markdown": format = .markdown
        case "plain-text": format = .plainText
        default: format = .html
        }
        let stage: UpdateOffer.Stage
        switch state.stage {
        case .downloaded: stage = .downloaded
        case .installing: stage = .installing
        default: stage = .notDownloaded
        }
        return UpdateOffer(
            version: item.displayVersionString,
            currentVersion: currentVersion,
            size: item.contentLength > 0 ? item.contentLength : nil,
            notes: item.itemDescription,
            notesFormat: format,
            fullNotesURL: item.fullReleaseNotesURL,
            infoURL: item.infoURL,
            isInformationOnly: item.isInformationOnlyUpdate,
            isCritical: item.isCriticalUpdate,
            stage: stage
        )
    }
}
#endif
