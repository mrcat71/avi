@testable import AppUI
import Foundation
import Testing

@Suite("Error notice text")
struct ErrorNoticeTextTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        let title: String
        let message: String?

        var testDescription: String {
            name
        }
    }

    static let cases: [Case] = [
        Case(
            name: "short message is the whole title",
            text: "The picked lines changed since they were shown.",
            title: "The picked lines changed since they were shown",
            message: nil
        ),
        Case(
            name: "short action and reason split at the colon",
            text: "Not a git repository: /tmp/x",
            title: "Not a git repository",
            message: "/tmp/x"
        ),
        Case(
            name: "action and reason split at the colon",
            text: "Could not push main to origin: ! [rejected] main -> main (fetch first)\nerror: failed to push some refs",
            title: "Could not push main to origin",
            message: "! [rejected] main -> main (fetch first)\nerror: failed to push some refs"
        ),
        Case(
            name: "first line of a list is the title",
            text: "These branches could not be deleted:\n\nfeature/a: not merged",
            title: "These branches could not be deleted",
            message: "feature/a: not merged"
        ),
        Case(
            name: "first sentence of a long line is the title",
            text: "Another remote operation is still running. Wait for it to finish, then try again, or cancel it from the toolbar first.",
            title: "Another remote operation is still running",
            message: "Wait for it to finish, then try again, or cancel it from the toolbar first."
        ),
        Case(
            name: "Git's own prefix is not a title",
            text: "fatal: unable to access 'https://example.com/repo.git/': Could not resolve host: example.com",
            title: ErrorNoticeText.fallbackTitle,
            message: "fatal: unable to access 'https://example.com/repo.git/': Could not resolve host: example.com"
        ),
        Case(name: "empty", text: "  \n", title: ErrorNoticeText.fallbackTitle, message: nil)
    ]

    @Test(arguments: cases)
    func splitsIntoTitleAndMessage(testCase: Case) {
        let parts = ErrorNoticeText.split(testCase.text)
        #expect(parts.title == testCase.title)
        #expect(parts.message == testCase.message)
    }

    @Test func longMessagesFold() {
        #expect(!AviNoticeCard.isLong("One line."))
        #expect(AviNoticeCard.isLong(String(repeating: "x", count: 200)))
        #expect(AviNoticeCard.isLong("1\n2\n3\n4"))
    }
}

@MainActor
@Suite("Notice center")
struct AviNoticeCenterTests {
    private func notice(_ id: String, title: String = "Title") -> AviNotice {
        AviNotice(id: id, symbol: "info", title: title)
    }

    @Test func showAppendsAndReplacesInPlace() {
        let center = AviNoticeCenter()
        center.show(notice("a"))
        center.show(notice("b"))
        center.show(notice("a", title: "Changed"))
        #expect(center.notices.map(\.id) == ["a", "b"])
        #expect(center.notices.first?.title == "Changed")
    }

    @Test func dismissRemovesOnlyThatNotice() {
        let center = AviNoticeCenter()
        center.show(notice("a"))
        center.show(notice("b"))
        center.dismiss(id: "a")
        #expect(center.notices.map(\.id) == ["b"])
    }

    @Test func attentionCountsOnlyShownNotices() {
        let center = AviNoticeCenter()
        center.callAttention(to: "missing")
        #expect(center.attention.isEmpty)
        center.show(notice("a"))
        center.callAttention(to: "a")
        center.callAttention(to: "a")
        #expect(center.attention["a"] == 2)
        center.dismiss(id: "a")
        #expect(center.attention["a"] == nil)
    }

    @Test func errorNoticeCopiesAndCloses() {
        var closed = false
        let notice = AviNotice.error(id: "e", text: "Could not save the patch: disk full") { closed = true }
        #expect(notice.title == "Could not save the patch")
        #expect(notice.message == "disk full")
        #expect(notice.tone == .error)
        #expect(notice.actions.map(\.title) == ["Copy"])
        notice.onDismiss?()
        #expect(closed)
    }

    @Test func workspaceErrorIsAWindowNotice() throws {
        let suite = "avi-notice-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = WorkspaceSession(git: Fixtures.clean(), defaults: defaults)
        #expect(session.notices.isEmpty)

        session.errorMessage = "Unable to save the workspace: disk full"
        let notices = session.notices
        #expect(notices.map(\.title) == ["Unable to save the workspace"])
        notices.first?.onDismiss?()
        #expect(session.errorMessage == nil)
    }
}
