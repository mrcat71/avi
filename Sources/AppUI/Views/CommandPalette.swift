import SwiftUI

struct CommandPalette: View {
    let commands: [AppCommand]
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                TextField("Type a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($queryFocused)
                    .onSubmit(runSelection)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(grouped.enumerated()), id: \.offset) { groupIndex, group in
                            sectionHeader(group.name)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                                let flatIndex = flatIndex(groupIndex: groupIndex, itemIndex: itemIndex)
                                CommandRow(
                                    command: item,
                                    isSelected: flatIndex == selectedIndex
                                ) {
                                    run(item)
                                }
                                .id(flatIndex)
                            }
                        }
                        if filtered.isEmpty {
                            Text("No matches")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .onChange(of: selectedIndex) { _, newIndex in
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(width: 540)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onAppear {
            queryFocused = true
        }
        .onKeyPress(.downArrow) {
            move(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            move(by: -1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private var filtered: [AppCommand] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return commands }
        return commands.filter { c in
            c.title.lowercased().contains(needle) ||
            c.group.lowercased().contains(needle) ||
            (c.subtitle?.lowercased().contains(needle) ?? false)
        }
    }

    private var grouped: [(name: String, items: [AppCommand])] {
        var seenGroups: [String] = []
        var byGroup: [String: [AppCommand]] = [:]
        for c in filtered {
            if byGroup[c.group] == nil {
                seenGroups.append(c.group)
                byGroup[c.group] = []
            }
            byGroup[c.group]?.append(c)
        }
        return seenGroups.map { (name: $0, items: byGroup[$0] ?? []) }
    }

    private func flatIndex(groupIndex: Int, itemIndex: Int) -> Int {
        var index = 0
        for i in 0..<groupIndex {
            index += grouped[i].items.count
        }
        return index + itemIndex
    }

    private func move(by delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    private func runSelection() {
        guard selectedIndex >= 0 && selectedIndex < filtered.count else { return }
        run(filtered[selectedIndex])
    }

    private func run(_ command: AppCommand) {
        isPresented = false
        command.perform()
    }

    private func sectionHeader(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

private struct CommandRow: View {
    let command: AppCommand
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: command.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Color.white : .primary)
                    if let subtitle = command.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
