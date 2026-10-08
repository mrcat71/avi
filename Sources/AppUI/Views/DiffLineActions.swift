import GitKit
import SwiftUI

/// What the Changes view lets you do with picked lines of a file's diff.
enum DiffLineCommand {
    case stage
    case unstage
    case discard
}

/// Picked-line actions for a diff, offered next to the selection:
/// selected lines, or the whole hunk around the caret.
struct DiffLineActions {
    enum Mode {
        /// The working tree's changes: stage or discard them.
        case unstaged
        /// The staged changes: unstage them.
        case staged
    }

    let mode: Mode
    let perform: (DiffLineCommand, Set<DiffLineKey>) -> Void
}

/// The buttons floating beside the picked lines.
struct DiffLineActionBar: View {
    let mode: DiffLineActions.Mode
    let isHunk: Bool
    let perform: (DiffLineCommand) -> Void

    var body: some View {
        HStack(spacing: 6) {
            switch mode {
            case .unstaged:
                button(isHunk ? "Stage Hunk" : "Stage Lines", prominent: true) { perform(.stage) }
                button(isHunk ? "Discard Hunk…" : "Discard Lines…", prominent: false) { perform(.discard) }
            case .staged:
                button(isHunk ? "Unstage Hunk" : "Unstage Lines", prominent: true) { perform(.unstage) }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6))
        .aviShadow(Glass.Elevation.raised.shadow)
        .fixedSize()
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .foregroundStyle(prominent ? Color.white : DS.Palette.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(prominent ? DS.Palette.accent : Color.primary.opacity(0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help(title))
    }

    private func help(_ title: String) -> String {
        switch title {
        case "Stage Lines": return "Stage only the selected lines"
        case "Stage Hunk": return "Stage this hunk; select lines to stage only those"
        case "Discard Lines…": return "Undo the selected lines in the working tree"
        case "Discard Hunk…": return "Undo this hunk in the working tree"
        case "Unstage Lines": return "Unstage only the selected lines"
        default: return "Unstage this hunk; select lines to unstage only those"
        }
    }
}
