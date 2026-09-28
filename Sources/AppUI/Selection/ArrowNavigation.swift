import SwiftUI

enum ArrowDirection {
    case up
    case down
}

/// Where Up or Down moves the selection in a file list that also shows folder
/// and heading rows. The keys go from file to file and pass over every other
/// row, so a folder never takes the selection.
///
/// - Parameters:
///   - rows: the list's row ids in display order, files and other rows alike.
///   - files: the ids in `rows` that are files.
///   - selection: the ids selected now. Down starts after the last of them and
///     Up before the first; with nothing selected, Down picks the first file
///     and Up the last.
/// - Returns: the file to select, or `nil` at either end of the list.
func arrowTarget(moving direction: ArrowDirection, rows: [String], files: Set<String>, selection: Set<String>) -> String? {
    let selected = rows.indices.filter { selection.contains(rows[$0]) }
    switch direction {
    case .down:
        let start = selected.last.map { $0 + 1 } ?? rows.startIndex
        return rows[start...].first(where: files.contains)
    case .up:
        let end = selected.first ?? rows.endIndex
        return rows[..<end].last(where: files.contains)
    }
}

extension View {
    /// Up and Down move a list's selection from file to file. The list itself
    /// would stop on every row, folders included, so the keys are taken before
    /// it sees them. An arrow with Shift or another modifier still reaches the
    /// list, so Shift extends the selection the usual way.
    ///
    /// `target` gives the row to select for a direction and the current
    /// selection, or `nil` to stay put. `didMove` runs after the selection moved.
    func arrowKeysStepThroughFiles(
        selection: Binding<Set<String>>,
        target: @escaping (ArrowDirection, Set<String>) -> String?,
        didMove: @escaping (String) -> Void = { _ in }
    ) -> some View {
        onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
            guard press.modifiers.isDisjoint(with: [.shift, .command, .option, .control]) else { return .ignored }
            let direction: ArrowDirection = press.key == .upArrow ? .up : .down
            if let row = target(direction, selection.wrappedValue) {
                selection.wrappedValue = [row]
                didMove(row)
            }
            return .handled
        }
    }
}
