import SwiftUI

/// Summary line plus optional body, shared by the commit panel and the plan
/// composer so both look and count the same way. One card holds both fields
/// and, when given, a row of actions along its bottom edge; the card's edge
/// lights up while either field has focus.
struct CommitMessageEditor<Actions: View>: View {
    @Binding var summary: String
    @Binding var messageBody: String
    var summaryPlaceholder = "feat(scope): short summary"
    private let actions: Actions
    private let hasActions: Bool

    @FocusState private var focusedField: Field?

    private enum Field {
        case summary
        case body
    }

    private let summaryWarn = 50
    private let summaryMax = 72

    init(
        summary: Binding<String>,
        messageBody: Binding<String>,
        summaryPlaceholder: String = "feat(scope): short summary",
        @ViewBuilder actions: () -> Actions
    ) {
        _summary = summary
        _messageBody = messageBody
        self.summaryPlaceholder = summaryPlaceholder
        self.actions = actions()
        hasActions = true
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Glass.Corner.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            summaryField
            Rectangle()
                .fill(DS.Palette.dividerSoft)
                .frame(height: 1)
                .padding(.horizontal, 10)
            bodyField
            if hasActions {
                actions
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
            }
        }
        .background(shape.fill(.regularMaterial))
        .overlay(
            shape.strokeBorder(
                focusedField == nil ? Color.primary.opacity(0.12) : DS.Palette.accent.opacity(0.55),
                lineWidth: focusedField == nil ? 0.6 : 1
            )
        )
        .animation(Glass.Motion.snappy, value: focusedField)
    }

    private var summaryField: some View {
        HStack(spacing: 0) {
            TextField(summaryPlaceholder, text: $summary)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($focusedField, equals: .summary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .accessibilityLabel("Commit summary")

            Text("\(summary.count) / \(summaryMax)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(counterColor)
                .padding(.trailing, 10)
                .accessibilityLabel("\(summary.count) of \(summaryMax) characters")
        }
    }

    private var bodyField: some View {
        TextEditor(text: $messageBody)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .focused($focusedField, equals: .body)
            .frame(minHeight: 50, idealHeight: 64, maxHeight: 100)
            .overlay {
                if messageBody.isEmpty {
                    Text("Optional details. Leave a blank line after the summary.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .accessibilityLabel("Commit description")
    }

    private var counterColor: Color {
        if summary.count > summaryMax {
            return .red
        }
        if summary.count > summaryWarn {
            return .orange
        }
        return .secondary
    }
}

extension CommitMessageEditor where Actions == EmptyView {
    init(summary: Binding<String>, messageBody: Binding<String>, summaryPlaceholder: String = "feat(scope): short summary") {
        _summary = summary
        _messageBody = messageBody
        self.summaryPlaceholder = summaryPlaceholder
        actions = EmptyView()
        hasActions = false
    }
}

/// Splits a full commit message into the summary line and the body, and joins
/// them back with the blank line Git expects. Every line survives the round trip.
enum CommitMessageParts {
    static func split(_ message: String) -> (summary: String, body: String) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        let summary = lines.first.map(String.init) ?? ""
        var rest = Array(lines.dropFirst())
        while let first = rest.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            rest.removeFirst()
        }
        return (summary, rest.joined(separator: "\n"))
    }

    static func join(summary: String, body: String) -> String {
        body.isEmpty ? summary : summary + "\n\n" + body
    }
}
