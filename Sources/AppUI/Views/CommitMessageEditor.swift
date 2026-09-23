import SwiftUI

/// Summary line plus optional body, shared by the commit panel and the plan
/// composer so both look and count the same way.
struct CommitMessageEditor: View {
    @Binding var summary: String
    @Binding var messageBody: String
    var summaryPlaceholder = "feat(scope): short summary"

    private let summaryWarn = 50
    private let summaryMax = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryField
            bodyField
        }
    }

    private var summaryField: some View {
        HStack(spacing: 0) {
            TextField(summaryPlaceholder, text: $summary)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .accessibilityLabel("Commit summary")

            Text("\(summary.count) / \(summaryMax)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(counterColor)
                .padding(.trailing, 8)
                .accessibilityLabel("\(summary.count) of \(summaryMax) characters")
        }
        .background(
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
        )
    }

    private var bodyField: some View {
        TextEditor(text: $messageBody)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
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
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
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
