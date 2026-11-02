import AppKit
import SwiftUI

/// A new version the feed offers, in the terms the update notice needs.
struct UpdateOffer: Equatable {
    enum Stage: Equatable {
        /// Found; nothing downloaded yet.
        case notDownloaded
        /// Downloaded in the background, not installing yet.
        case downloaded
        /// Downloaded and set to install when Avi quits.
        case installing
    }

    enum NotesFormat: Equatable {
        case markdown
        case html
        case plainText
    }

    var version: String
    var currentVersion: String
    /// Bytes to download, when the feed says.
    var size: UInt64?
    var notes: String?
    var notesFormat: NotesFormat = .markdown
    var fullNotesURL: URL?
    var infoURL: URL?
    /// The feed only points at a website; there is nothing to install.
    var isInformationOnly = false
    var isCritical = false
    var stage: Stage = .notDownloaded
}

/// Each step of an update, as the update notice shows it.
enum UpdatePhase: Equatable {
    /// First launch: may Avi check by itself?
    case permission
    case checking
    case available(UpdateOffer)
    case downloading(UpdateOffer?, received: UInt64, expected: UInt64?)
    case preparing(UpdateOffer?, progress: Double?)
    case ready(UpdateOffer?)
    case installing(UpdateOffer?, canRetry: Bool)
    case upToDate(currentVersion: String)
    /// No update for this Mac for another reason, such as its macOS version.
    case unavailable(title: String, message: String?)
    case failed(message: String)
    case installed
}

/// Your answer to an update offer, apart from Sparkle's own type.
enum UpdateChoice: Equatable {
    case install
    case later
    case skip
}

/// What the notice shows right after you answer, until Sparkle's next step
/// arrives, and whether the relaunch should follow without asking again.
enum UpdateFlow {
    static func after(_ choice: UpdateChoice, in phase: UpdatePhase?, offer: UpdateOffer?) -> (phase: UpdatePhase?, relaunchWhenReady: Bool) {
        guard choice == .install else { return (nil, false) }
        guard case .available(let found)? = phase else {
            return (.installing(offer, canRetry: false), false)
        }
        switch found.stage {
        case .notDownloaded:
            return (.downloading(found, received: 0, expected: nil), false)
        case .downloaded:
            // You already chose to relaunch; unpacking comes first.
            return (.preparing(found, progress: nil), true)
        case .installing:
            return (.installing(found, canRetry: false), false)
        }
    }
}

/// What the buttons of the update notice do. The driver answers Sparkle.
struct UpdateNoticeHandlers {
    var install: @MainActor () -> Void = {}
    var later: @MainActor () -> Void = {}
    var skip: @MainActor () -> Void = {}
    var cancel: @MainActor () -> Void = {}
    var acknowledge: @MainActor () -> Void = {}
    var allowAutomaticChecks: @MainActor (Bool) -> Void = { _ in }
    var retry: @MainActor () -> Void = {}
    var retryQuit: @MainActor () -> Void = {}
    var openURL: @MainActor (URL) -> Void = { _ in }
}

/// Builds the update notice for each step. Kept apart from Sparkle so every
/// step can be checked and drawn without a feed.
@MainActor
enum UpdateNotice {
    static let id = "app-update"

    static func make(_ phase: UpdatePhase, handlers: UpdateNoticeHandlers) -> AviNotice {
        switch phase {
        case .permission:
            return AviNotice(
                id: id,
                symbol: "arrow.triangle.2.circlepath",
                title: "Check for updates automatically?",
                message: "Avi looks for a new version once a day and asks before installing it. Settings > General can change this later.",
                actions: [
                    .init(title: "Not Now") { handlers.allowAutomaticChecks(false) },
                    .init(title: "Check Automatically", role: .primary) { handlers.allowAutomaticChecks(true) }
                ]
            )
        case .checking:
            return AviNotice(
                id: id,
                symbol: "arrow.triangle.2.circlepath",
                title: "Checking for updates…",
                progress: .indeterminate,
                actions: [.init(title: "Cancel") { handlers.cancel() }]
            )
        case .available(let offer):
            return available(offer, handlers: handlers)
        case let .downloading(offer, received, expected):
            let fraction = expected.flatMap { $0 > 0 ? Double(received) / Double($0) : nil }
            return AviNotice(
                id: id,
                symbol: "arrow.down",
                title: "Downloading \(name(offer))…",
                message: downloadProgress(received: received, expected: expected),
                progress: fraction.map { .fraction(min($0, 1)) } ?? .indeterminate,
                actions: [.init(title: "Cancel") { handlers.cancel() }]
            )
        case let .preparing(offer, progress):
            return AviNotice(
                id: id,
                symbol: "shippingbox.fill",
                title: "Preparing \(name(offer))…",
                message: "Checking the download's signature and unpacking it.",
                progress: progress.map { .fraction($0) } ?? .indeterminate
            )
        case .ready(let offer):
            return AviNotice(
                id: id,
                tone: .success,
                symbol: "arrow.clockwise",
                title: "\(name(offer)) is ready",
                message: "Relaunch to finish updating, or Avi installs it the next time you quit. Your open repositories reopen afterwards.",
                actions: [
                    .init(title: "Later") { handlers.later() },
                    .init(title: "Relaunch to Update", role: .primary) { handlers.install() }
                ],
                onDismiss: { handlers.later() }
            )
        case let .installing(offer, canRetry):
            return AviNotice(
                id: id,
                symbol: "shippingbox.fill",
                title: "Installing \(name(offer))…",
                message: "Avi quits, installs the update, and opens again.",
                progress: .indeterminate,
                actions: canRetry ? [.init(title: "Quit and Install") { handlers.retryQuit() }] : []
            )
        case .upToDate(let current):
            return AviNotice(
                id: id,
                tone: .success,
                symbol: "checkmark",
                title: "Avi is up to date",
                message: "\(current) is the newest version.",
                onDismiss: { handlers.acknowledge() },
                autoDismiss: .seconds(5)
            )
        case let .unavailable(title, message):
            return AviNotice(
                id: id,
                symbol: "info",
                title: title,
                message: message,
                onDismiss: { handlers.acknowledge() }
            )
        case .failed(let message):
            return AviNotice(
                id: id,
                tone: .error,
                symbol: "exclamationmark.triangle.fill",
                title: "The update did not finish",
                message: message,
                actions: [.init(title: "Try Again", role: .primary) { handlers.retry() }],
                onDismiss: { handlers.acknowledge() }
            )
        case .installed:
            return AviNotice(
                id: id,
                tone: .success,
                symbol: "checkmark",
                title: "Avi is updated",
                onDismiss: { handlers.acknowledge() },
                autoDismiss: .seconds(4)
            )
        }
    }

    private static func available(_ offer: UpdateOffer, handlers: UpdateNoticeHandlers) -> AviNotice {
        var notice = AviNotice(
            id: id,
            symbol: "arrow.down",
            title: "Avi \(offer.version) is available",
            onDismiss: { handlers.later() }
        )
        notice.details = details(offer, handlers: handlers)
        let skip = AviNotice.Action(title: "Skip This Version") { handlers.skip() }
        let later = AviNotice.Action(title: "Later") { handlers.later() }

        if offer.isInformationOnly {
            notice.message = "You have \(offer.currentVersion). This version is available from its website."
            notice.actions = [skip]
            if let url = offer.infoURL {
                notice.actions.append(.init(title: "Learn More", role: .primary) {
                    handlers.openURL(url)
                    handlers.later()
                })
            }
            return notice
        }

        switch offer.stage {
        case .notDownloaded:
            var message = "You have \(offer.currentVersion)."
            if let size = offer.size {
                message += " The download is \(byteCount(size))."
            }
            notice.message = offer.isCritical ? "An important update. " + message : message
            notice.actions = [later, .init(title: "Update", role: .primary) { handlers.install() }]
        case .downloaded:
            notice.title = "Avi \(offer.version) is ready to install"
            notice.message = "It downloaded in the background. Relaunch to finish updating; your open repositories reopen afterwards."
            notice.actions = [later, .init(title: "Relaunch to Update", role: .primary) { handlers.install() }]
        case .installing:
            notice.title = "Avi \(offer.version) is ready to install"
            notice.message = "Avi installs it the next time you quit, or relaunch now."
            notice.actions = [later, .init(title: "Relaunch to Update", role: .primary) { handlers.install() }]
        }
        if !offer.isCritical, offer.stage != .installing {
            notice.actions.insert(skip, at: 0)
        }
        if offer.isCritical {
            notice.tone = .warning
        }
        return notice
    }

    private static func details(_ offer: UpdateOffer, handlers: UpdateNoticeHandlers) -> AviNotice.Details? {
        let blocks = offer.notes.map { ReleaseNotes.blocks(from: $0, format: offer.notesFormat) } ?? []
        guard !blocks.isEmpty || offer.fullNotesURL != nil else { return nil }
        return AviNotice.Details(
            title: "What's New in \(offer.version)",
            content: AnyView(ReleaseNotesView(blocks: blocks, fullNotesURL: offer.fullNotesURL, openURL: handlers.openURL))
        )
    }

    private static func name(_ offer: UpdateOffer?) -> String {
        offer.map { "Avi \($0.version)" } ?? "the update"
    }

    static func downloadProgress(received: UInt64, expected: UInt64?) -> String {
        guard let expected, expected > 0 else {
            return received > 0 ? "\(byteCount(received)) so far" : "Starting the download"
        }
        return "\(byteCount(min(received, expected))) of \(byteCount(expected))"
    }

    static func byteCount(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
}

/// Release notes from the feed: Avi's are the version's CHANGELOG section,
/// in Markdown.
enum ReleaseNotes {
    enum Block: Equatable {
        case heading(String)
        case bullet(String, level: Int)
        case paragraph(String)
    }

    @MainActor
    static func blocks(from text: String, format: UpdateOffer.NotesFormat) -> [Block] {
        switch format {
        case .markdown:
            return markdownBlocks(text)
        case .plainText:
            return paragraphs(text)
        case .html:
            return paragraphs(plainText(fromHTML: text))
        }
    }

    /// Headings, list items (nested by indentation), and paragraphs. Inline
    /// Markdown stays in the text for the view to render.
    static func markdownBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = heading(line) {
                flushParagraph()
                blocks.append(.heading(heading))
            } else if let item = listItem(rawLine) {
                flushParagraph()
                blocks.append(.bullet(item.text, level: item.level))
            } else if case let .bullet(previous, level)? = blocks.last, paragraph.isEmpty, rawLine.first?.isWhitespace == true {
                // An indented line continues the list item above it.
                blocks[blocks.count - 1] = .bullet(previous + " " + line, level: level)
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1 ... 6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func listItem(_ rawLine: String) -> (text: String, level: Int)? {
        let indent = rawLine.prefix { $0 == " " || $0 == "\t" }
        let width = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let line = rawLine.dropFirst(indent.count)
        var text: Substring?
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            text = line.dropFirst(2)
        } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                  line[line.index(after: dot)...].first == " " {
            text = line[line.index(dot, offsetBy: 2)...]
        }
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : (trimmed, min(width / 2, 3))
    }

    private static func paragraphs(_ text: String) -> [Block] {
        text.components(separatedBy: "\n\n")
            .map { $0.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .map(Block.paragraph)
    }

    @MainActor
    private static func plainText(fromHTML html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              )
        else { return html }
        return attributed.string
    }
}

/// The release notes inside the update notice.
struct ReleaseNotesView: View {
    let blocks: [ReleaseNotes.Block]
    var fullNotesURL: URL?
    var openURL: @MainActor (URL) -> Void = { _ in }

    @Environment(\.aviDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .heading(let title):
                    Text(title)
                        .aviLabel(density)
                        .padding(.top, index == 0 ? 0 : 6)
                case let .bullet(text, level):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(level == 0 ? "•" : "◦")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(Self.inline(text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(level) * 12)
                case .paragraph(let text):
                    Text(Self.inline(text))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let fullNotesURL {
                Button {
                    openURL(fullNotesURL)
                } label: {
                    Label("Full Changelog", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Palette.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(fullNotesURL.absoluteString)
                .padding(.top, blocks.isEmpty ? 0 : 4)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(DS.Palette.textPrimary)
        .textSelection(.enabled)
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// The title, then a small icon after it.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
