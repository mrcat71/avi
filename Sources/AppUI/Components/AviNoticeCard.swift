import Accessibility
import GitKit
import SwiftUI

/// One notice: a tinted badge (or progress ring), the title, the message,
/// optional details, the buttons, and a close button. The title ticks over
/// to the next one when it changes, as an update moves from downloading to
/// ready.
struct AviNoticeCard: View {
    static let width: CGFloat = 400
    static let cornerRadius: CGFloat = 16

    let notice: AviNotice
    /// Changes when the notice should draw attention to itself again.
    var attention = 0

    @State private var isHovering = false
    @State private var showsFullMessage = false
    @State private var showsDetails: Bool
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `expandsDetails` opens the details from the start, for screenshots.
    init(notice: AviNotice, attention: Int = 0, expandsDetails: Bool = false) {
        self.notice = notice
        self.attention = attention
        _showsDetails = State(initialValue: expandsDetails)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AviNoticeBadge(symbol: notice.symbol, tint: notice.tone.color, progress: notice.progress)
                VStack(alignment: .leading, spacing: 3) {
                    title
                    if let message = notice.message, !message.isEmpty {
                        messageView(message)
                    }
                    if let details = notice.details {
                        detailsView(details)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let onDismiss = notice.onDismiss {
                    closeButton(onDismiss)
                        .padding(.trailing, -4)
                }
            }
            if !notice.actions.isEmpty {
                actions
            }
        }
        .padding(12)
        .frame(width: Self.width)
        .modifier(AviFloatingSurface(cornerRadius: Self.cornerRadius))
        .scaleEffect(isPulsing ? 1.025 : 1)
        .onHover { isHovering = $0 }
        .task(id: AutoDismissKey(id: notice.id, title: notice.title, isPaused: isHovering || showsDetails || showsFullMessage)) {
            await autoDismiss()
        }
        .onChange(of: attention) { _, _ in
            pulse()
        }
        // A notice appears without taking focus; VoiceOver reads it out.
        .onAppear {
            AccessibilityNotification.Announcement(notice.title).post()
        }
        .onChange(of: notice.title) { _, title in
            AccessibilityNotification.Announcement(title).post()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.title)
        .accessibilityValue(progressDescription)
    }

    // MARK: - Parts

    private var title: some View {
        ZStack(alignment: .leading) {
            Text(notice.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(notice.title)
                .transition(reduceMotion ? .opacity : .push(from: .bottom))
        }
        .clipped()
        .animation(Glass.Motion.standard, value: notice.title)
        .padding(.top, 1)
    }

    @ViewBuilder
    private func messageView(_ message: String) -> some View {
        let isLong = Self.isLong(message)
        VStack(alignment: .leading, spacing: 4) {
            if showsFullMessage {
                HuggingScrollView(maxHeight: 180) {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(isLong ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if isLong {
                disclosureButton(showsFullMessage ? "Show Less" : "Show Full Message", isOpen: showsFullMessage) {
                    showsFullMessage.toggle()
                }
            }
        }
    }

    private func detailsView(_ details: AviNotice.Details) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            disclosureButton(details.title, isOpen: showsDetails) {
                showsDetails.toggle()
            }
            if showsDetails {
                HuggingScrollView(maxHeight: 220) {
                    details.content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 4)
    }

    private func disclosureButton(_ title: String, isOpen: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Glass.Motion.standard) {
                action()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.Palette.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ForEach(notice.actions) { action in
                Button(action.title, role: action.role == .destructive ? .destructive : nil) {
                    action.perform()
                }
                .buttonStyle(AviPopupButtonStyle(emphasis: action.role == .secondary ? .secondary : .prominent, size: .small))
            }
        }
    }

    private func closeButton(_ onDismiss: @escaping @MainActor () -> Void) -> some View {
        AviNoticeCloseButton(action: onDismiss)
    }

    // MARK: - Behavior

    /// Long messages start folded to three lines.
    static func isLong(_ message: String) -> Bool {
        message.count > 180 || message.split(whereSeparator: \.isNewline).count > 3
    }

    private struct AutoDismissKey: Equatable {
        let id: String
        let title: String
        let isPaused: Bool
    }

    private func autoDismiss() async {
        guard let delay = notice.autoDismiss, let onDismiss = notice.onDismiss,
              !isHovering, !showsDetails, !showsFullMessage else { return }
        do {
            try await Task.safeSleep(for: delay)
        } catch {
            return
        }
        onDismiss()
    }

    private func pulse() {
        guard !reduceMotion else { return }
        withAnimation(Glass.Motion.snappy) {
            isPulsing = true
        }
        Task { @MainActor in
            try? await Task.safeSleep(for: .milliseconds(180))
            withAnimation(Glass.Motion.bouncy) {
                isPulsing = false
            }
        }
    }

    private var progressDescription: String {
        switch notice.progress {
        case .fraction(let value):
            return "\(Int((min(max(value, 0), 1) * 100).rounded())) percent"
        case .indeterminate:
            return "In progress"
        case nil:
            return ""
        }
    }
}

/// As tall as its content up to `maxHeight`, then scrolling.
private struct HuggingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content()
            ScrollView {
                content()
            }
        }
        .frame(maxHeight: maxHeight)
    }
}

/// The round badge at a notice's leading edge. With progress it rings the
/// symbol: filling as a download arrives, spinning while the length is unknown.
struct AviNoticeBadge: View {
    let symbol: String
    let tint: Color
    var progress: AviNotice.Progress?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 30
    private let ringWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
            if let progress {
                Circle()
                    .inset(by: ringWidth / 2)
                    .stroke(tint.opacity(0.18), lineWidth: ringWidth)
                ring(progress)
            }
            Image(systemName: symbol)
                .font(.system(size: progress == nil ? 13 : 11, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func ring(_ progress: AviNotice.Progress) -> some View {
        switch progress {
        case .fraction(let value):
            Circle()
                .inset(by: ringWidth / 2)
                .trim(from: 0, to: min(max(value, 0.02), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: value)
        case .indeterminate:
            if reduceMotion {
                arc(rotation: 0)
            } else {
                TimelineView(.animation) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
                    arc(rotation: turn * 360)
                }
            }
        }
    }

    private func arc(rotation: Double) -> some View {
        Circle()
            .inset(by: ringWidth / 2)
            .trim(from: 0, to: 0.28)
            .stroke(tint, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
            .rotationEffect(.degrees(rotation - 90))
    }
}

/// The close button in a notice's corner.
private struct AviNoticeCloseButton: View {
    let action: @MainActor () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(isHovering ? 0.10 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Close")
        .accessibilityLabel("Close")
    }
}

/// The surface of things that float over the window, notices and the command
/// palette: Liquid Glass on macOS 26 and later, a material card with a lit rim
/// before that, and a solid one with Reduce Transparency.
struct AviFloatingSurface: ViewModifier {
    var cornerRadius: CGFloat = AviNoticeCard.cornerRadius

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        glass(content, shape: shape)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.40 : 0.16), radius: 22, x: 0, y: 10)
    }

    @ViewBuilder
    private func glass(_ content: Content, shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(DS.Palette.surfaceRaised))
                .overlay(shape.strokeBorder(DS.Palette.dividerStrong, lineWidth: 0.6))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                // A wash of the window color keeps text readable over a busy diff.
                content
                    .background(shape.fill(DS.Palette.surface.opacity(0.35)))
                    .glassEffect(.regular, in: shape)
            } else {
                materialCard(content, shape: shape)
            }
            #else
            materialCard(content, shape: shape)
            #endif
        }
    }

    private func materialCard(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background {
                shape
                    .fill(.regularMaterial)
                    .overlay(shape.fill(Glass.topHighlight))
            }
            .overlay(shape.strokeBorder(Glass.edgeStroke, lineWidth: 0.6))
    }
}

/// The notices of one window, stacked at the top of its content.
struct AviNoticeStack: View {
    let notices: [AviNotice]
    var attention: [String: Int] = [:]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(notices) { notice in
                AviNoticeCard(notice: notice, attention: attention[notice.id] ?? 0)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        )
                    )
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .animation(Glass.Motion.standard, value: notices.map(\.id))
    }
}

extension View {
    /// Floats this window's notices, then the app's, at the top of the view.
    /// App notices show only in the window you work in.
    func aviNotices(_ local: [AviNotice] = []) -> some View {
        modifier(AviNoticeHost(local: local))
    }
}

private struct AviNoticeHost: ViewModifier {
    let local: [AviNotice]
    @Environment(\.controlActiveState) private var activeState

    func body(content: Content) -> some View {
        let center = AviNoticeCenter.shared
        let shared = activeState == .inactive ? [] : center.notices
        content
            .overlay(alignment: .top) {
                AviNoticeStack(notices: local + shared, attention: center.attention)
            }
    }
}
