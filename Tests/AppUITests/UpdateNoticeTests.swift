@testable import AppUI
import Foundation
import Testing

@MainActor
@Suite("Update notice")
struct UpdateNoticeTests {
    nonisolated static let offer = UpdateOffer(
        version: "1.5.0",
        currentVersion: "1.4.2",
        size: 7_637_599,
        notes: "### Added\n- Notices",
        fullNotesURL: URL(string: "https://example.com/CHANGELOG.md"),
        infoURL: URL(string: "https://example.com/avi")
    )

    struct Step: Sendable, CustomTestStringConvertible {
        let name: String
        let phase: UpdatePhase
        let title: String
        let actions: [String]
        let hasClose: Bool
        let tone: AviNotice.Tone

        var testDescription: String {
            name
        }
    }

    nonisolated static let steps: [Step] = [
        Step(
            name: "permission", phase: .permission, title: "Check for updates automatically?",
            actions: ["Not Now", "Check Automatically"], hasClose: false, tone: .info
        ),
        Step(
            name: "checking", phase: .checking, title: "Checking for updates…",
            actions: ["Cancel"], hasClose: false, tone: .info
        ),
        Step(
            name: "found, not downloaded", phase: .available(offer), title: "Avi 1.5.0 is available",
            actions: ["Skip This Version", "Later", "Update"], hasClose: true, tone: .info
        ),
        Step(
            name: "downloading", phase: .downloading(offer, received: 1024, expected: 4096), title: "Downloading Avi 1.5.0…",
            actions: ["Cancel"], hasClose: false, tone: .info
        ),
        Step(
            name: "preparing", phase: .preparing(offer, progress: 0.5), title: "Preparing Avi 1.5.0…",
            actions: [], hasClose: false, tone: .info
        ),
        Step(
            name: "ready", phase: .ready(offer), title: "Avi 1.5.0 is ready",
            actions: ["Later", "Relaunch to Update"], hasClose: true, tone: .success
        ),
        Step(
            name: "installing, quit refused", phase: .installing(offer, canRetry: true), title: "Installing Avi 1.5.0…",
            actions: ["Quit and Install"], hasClose: false, tone: .info
        ),
        Step(
            name: "installing", phase: .installing(nil, canRetry: false), title: "Installing the update…",
            actions: [], hasClose: false, tone: .info
        ),
        Step(
            name: "up to date", phase: .upToDate(currentVersion: "1.4.2"), title: "Avi is up to date",
            actions: [], hasClose: true, tone: .success
        ),
        Step(
            name: "failed", phase: .failed(message: "The feed is not signed."), title: "The update did not finish",
            actions: ["Try Again"], hasClose: true, tone: .error
        )
    ]

    @Test(arguments: steps)
    func eachStepHasItsTitleAndButtons(step: Step) {
        let notice = UpdateNotice.make(step.phase, handlers: UpdateNoticeHandlers())
        #expect(notice.id == UpdateNotice.id)
        #expect(notice.title == step.title)
        #expect(notice.actions.map(\.title) == step.actions)
        #expect((notice.onDismiss != nil) == step.hasClose)
        #expect(notice.tone == step.tone)
    }

    @Test func buttonsAnswerSparkleThroughTheHandlers() {
        var calls: [String] = []
        let handlers = UpdateNoticeHandlers(
            install: { calls.append("install") },
            later: { calls.append("later") },
            skip: { calls.append("skip") }
        )
        let notice = UpdateNotice.make(.available(Self.offer), handlers: handlers)
        for action in notice.actions {
            action.perform()
        }
        notice.onDismiss?()
        #expect(calls == ["skip", "later", "install", "later"])
    }

    @Test func downloadShowsItsShareOnceTheLengthIsKnown() {
        let known = UpdateNotice.make(.downloading(Self.offer, received: 1024, expected: 4096), handlers: UpdateNoticeHandlers())
        #expect(known.progress == .fraction(0.25))
        #expect(known.message == UpdateNotice.downloadProgress(received: 1024, expected: 4096))

        let unknown = UpdateNotice.make(.downloading(Self.offer, received: 0, expected: nil), handlers: UpdateNoticeHandlers())
        #expect(unknown.progress == .indeterminate)
        #expect(unknown.message == "Starting the download")
    }

    @Test func downloadProgressNamesBothSizes() {
        let text = UpdateNotice.downloadProgress(received: 3_145_728, expected: 7_637_599)
        #expect(text == "\(UpdateNotice.byteCount(3_145_728)) of \(UpdateNotice.byteCount(7_637_599))")
        // More bytes than announced never reads as more than the whole.
        let over = UpdateNotice.downloadProgress(received: 9000, expected: 4000)
        #expect(over == "\(UpdateNotice.byteCount(4000)) of \(UpdateNotice.byteCount(4000))")
    }

    @Test func foundUpdateSaysWhatYouHaveAndTheSize() {
        let notice = UpdateNotice.make(.available(Self.offer), handlers: UpdateNoticeHandlers())
        #expect(notice.message == "You have 1.4.2. The download is \(UpdateNotice.byteCount(7_637_599)).")
        #expect(notice.details?.title == "What's New in 1.5.0")
    }

    @Test func criticalUpdateCannotBeSkipped() {
        var offer = Self.offer
        offer.isCritical = true
        let notice = UpdateNotice.make(.available(offer), handlers: UpdateNoticeHandlers())
        #expect(notice.actions.map(\.title) == ["Later", "Update"])
        #expect(notice.tone == .warning)
    }

    @Test func downloadedUpdateRelaunches() {
        var offer = Self.offer
        offer.stage = .downloaded
        let notice = UpdateNotice.make(.available(offer), handlers: UpdateNoticeHandlers())
        #expect(notice.title == "Avi 1.5.0 is ready to install")
        #expect(notice.actions.map(\.title) == ["Skip This Version", "Later", "Relaunch to Update"])

        offer.stage = .installing
        let installing = UpdateNotice.make(.available(offer), handlers: UpdateNoticeHandlers())
        #expect(installing.actions.map(\.title) == ["Later", "Relaunch to Update"])
    }

    @Test func informationOnlyUpdateOpensItsPage() throws {
        var offer = Self.offer
        offer.isInformationOnly = true
        var opened: [URL] = []
        var calls: [String] = []
        let handlers = UpdateNoticeHandlers(later: { calls.append("later") }, openURL: { opened.append($0) })
        let notice = UpdateNotice.make(.available(offer), handlers: handlers)
        #expect(notice.actions.map(\.title) == ["Skip This Version", "Learn More"])
        notice.actions.last?.perform()
        #expect(try opened == [#require(URL(string: "https://example.com/avi"))])
        #expect(calls == ["later"])
    }

    @Test func upToDateClosesByItself() {
        let notice = UpdateNotice.make(.upToDate(currentVersion: "1.4.2"), handlers: UpdateNoticeHandlers())
        #expect(notice.autoDismiss != nil)
        #expect(notice.message == "1.4.2 is the newest version.")
    }

    @Test func tryAgainRetries() {
        var calls: [String] = []
        let handlers = UpdateNoticeHandlers(acknowledge: { calls.append("acknowledge") }, retry: { calls.append("retry") })
        let notice = UpdateNotice.make(.failed(message: "Offline."), handlers: handlers)
        notice.actions.first?.perform()
        notice.onDismiss?()
        #expect(calls == ["retry", "acknowledge"])
    }
}

@Suite("Update flow")
struct UpdateFlowTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let choice: UpdateChoice
        let stage: UpdateOffer.Stage?
        let next: UpdatePhase?
        let relaunchWhenReady: Bool

        var testDescription: String {
            name
        }
    }

    nonisolated static let offer = UpdateNoticeTests.offer

    nonisolated static func offer(_ stage: UpdateOffer.Stage) -> UpdateOffer {
        var offer = offer
        offer.stage = stage
        return offer
    }

    nonisolated static let cases: [Case] = [
        Case(
            name: "update starts the download", choice: .install, stage: .notDownloaded,
            next: .downloading(offer(.notDownloaded), received: 0, expected: nil), relaunchWhenReady: false
        ),
        Case(
            name: "a downloaded update unpacks, then relaunches without asking again", choice: .install, stage: .downloaded,
            next: .preparing(offer(.downloaded), progress: nil), relaunchWhenReady: true
        ),
        Case(
            name: "an update set to install on quit relaunches now", choice: .install, stage: .installing,
            next: .installing(offer(.installing), canRetry: false), relaunchWhenReady: false
        ),
        Case(name: "relaunch from ready installs", choice: .install, stage: nil, next: .installing(offer, canRetry: false), relaunchWhenReady: false),
        Case(name: "later hides the notice", choice: .later, stage: .notDownloaded, next: nil, relaunchWhenReady: false),
        Case(name: "skip hides the notice", choice: .skip, stage: .downloaded, next: nil, relaunchWhenReady: false)
    ]

    @Test(arguments: cases)
    func answerMovesToTheNextStep(testCase: Case) {
        let phase: UpdatePhase = testCase.stage.map { .available(Self.offer($0)) } ?? .ready(Self.offer)
        let next = UpdateFlow.after(testCase.choice, in: phase, offer: Self.offer)
        #expect(next.phase == testCase.next)
        #expect(next.relaunchWhenReady == testCase.relaunchWhenReady)
    }
}

@MainActor
@Suite("Release notes")
struct ReleaseNotesTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let markdown: String
        let blocks: [ReleaseNotes.Block]

        var testDescription: String {
            name
        }
    }

    nonisolated static let cases: [Case] = [
        Case(
            name: "changelog section",
            markdown: "### Added\n- One `thing`.\n- **Two**.\n\n### Fixed\n- Three.",
            blocks: [.heading("Added"), .bullet("One `thing`.", level: 0), .bullet("**Two**.", level: 0), .heading("Fixed"), .bullet("Three.", level: 0)]
        ),
        Case(
            name: "nested and numbered items",
            markdown: "1. First\n  - Inner\n2. Second",
            blocks: [.bullet("First", level: 0), .bullet("Inner", level: 1), .bullet("Second", level: 0)]
        ),
        Case(
            name: "a wrapped item continues on the next line",
            markdown: "- A long item\n  that wraps.\n- Next",
            blocks: [.bullet("A long item that wraps.", level: 0), .bullet("Next", level: 0)]
        ),
        Case(
            name: "paragraphs join their lines",
            markdown: "Line one\nline two.\n\nAnother paragraph.",
            blocks: [.paragraph("Line one line two."), .paragraph("Another paragraph.")]
        ),
        Case(
            name: "a hash without a space is text",
            markdown: "#hashtag and #1",
            blocks: [.paragraph("#hashtag and #1")]
        ),
        Case(name: "empty notes", markdown: "\n\n", blocks: [])
    ]

    @Test(arguments: cases)
    func markdownBecomesBlocks(testCase: Case) {
        #expect(ReleaseNotes.markdownBlocks(testCase.markdown) == testCase.blocks)
    }

    @Test func plainTextKeepsItsParagraphs() {
        #expect(ReleaseNotes.blocks(from: "One\ntwo\n\nThree", format: .plainText) == [.paragraph("One two"), .paragraph("Three")])
    }

    @Test func htmlBecomesText() {
        let blocks = ReleaseNotes.blocks(from: "<p>Fixed <b>pushes</b>.</p>", format: .html)
        #expect(blocks == [.paragraph("Fixed pushes.")])
    }
}
