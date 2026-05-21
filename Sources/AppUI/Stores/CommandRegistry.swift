import AppKit
import Foundation
import GitKit

/// A single action exposable in the command palette.
struct AppCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let group: String
    let symbol: String
    let perform: @MainActor () -> Void
}

/// Builds the list of available commands for the current repository and selection state.
enum CommandRegistry {
    @MainActor
    static func commands(
        store: RepositoryStore,
        setSelection: @escaping (RepositorySelection) -> Void,
        openCreateBranch: @escaping () -> Void
    ) -> [AppCommand] {
        var result: [AppCommand] = []

        // View navigation
        result.append(AppCommand(id: "view.localChanges", title: "Go to Local Changes", subtitle: nil, group: "View", symbol: "pencil") {
            setSelection(.localChanges)
        })
        result.append(AppCommand(id: "view.allCommits", title: "Go to All Commits", subtitle: nil, group: "View", symbol: "clock.arrow.circlepath") {
            setSelection(.allCommits)
        })
        result.append(AppCommand(id: "view.settings", title: "Open Settings…", subtitle: "Cmd-,", group: "View", symbol: "gear") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        })

        // File / repository
        result.append(AppCommand(id: "repo.refresh", title: "Refresh", subtitle: "Reload status, refs, and history", group: "Repository", symbol: "arrow.clockwise") {
            Task { await store.refresh() }
        })
        result.append(AppCommand(id: "repo.openFolder", title: "Open Repository Folder", subtitle: store.root?.path, group: "Repository", symbol: "folder") {
            if let root = store.root {
                NSWorkspace.shared.open(root)
            }
        })

        // Working copy
        if store.canStageAll {
            result.append(AppCommand(id: "wc.stageAll", title: "Stage All", subtitle: nil, group: "Working Copy", symbol: "plus.rectangle.on.rectangle") {
                Task { await store.stageAll() }
            })
        }
        if store.canUnstageAll {
            result.append(AppCommand(id: "wc.unstageAll", title: "Unstage All", subtitle: nil, group: "Working Copy", symbol: "minus.rectangle") {
                Task { await store.unstageAll() }
            })
        }
        if store.canCommit {
            result.append(AppCommand(id: "wc.commit", title: store.amend ? "Amend Commit" : "Commit", subtitle: nil, group: "Working Copy", symbol: "checkmark") {
                Task { await store.commit() }
            })
        }

        // Branches
        result.append(AppCommand(id: "branch.create", title: "Create Branch…", subtitle: nil, group: "Branch", symbol: "plus") {
            openCreateBranch()
        })

        if let current = store.branch?.name {
            result.append(AppCommand(id: "branch.pushCurrent", title: "Push \(current)", subtitle: store.branch?.upstream, group: "Branch", symbol: "arrow.up.to.line") {
                Task { await store.push() }
            })
            result.append(AppCommand(id: "branch.pullCurrent", title: "Pull \(current)", subtitle: store.branch?.upstream, group: "Branch", symbol: "arrow.down.to.line") {
                Task { await store.pull() }
            })
        }

        for ref in store.refs.localBranches where !ref.isCurrent {
            result.append(AppCommand(id: "branch.checkout.\(ref.name)", title: "Checkout \(ref.name)", subtitle: ref.upstream, group: "Branch", symbol: "arrow.triangle.branch") {
                Task { await store.checkout(ref) }
            })
        }

        // Remote
        if !store.remotes.isEmpty {
            result.append(AppCommand(id: "remote.fetchAll", title: "Fetch All Remotes", subtitle: nil, group: "Remote", symbol: "arrow.down") {
                Task { await store.fetch(remote: nil) }
            })
        }
        for remote in store.remotes {
            result.append(AppCommand(id: "remote.fetch.\(remote.name)", title: "Fetch \(remote.name)", subtitle: remote.fetchURL, group: "Remote", symbol: "arrow.down") {
                Task { await store.fetch(remote: remote.name) }
            })
        }

        // History filters
        result.append(AppCommand(id: "history.scopeCurrent", title: "History: Current Branch", subtitle: nil, group: "History", symbol: "line.3.horizontal.decrease") {
            Task { await store.setHistoryFilter(HistoryFilter(scope: .currentBranch, hideMerges: store.historyFilter.hideMerges)) }
        })
        result.append(AppCommand(id: "history.scopeAll", title: "History: All Branches", subtitle: nil, group: "History", symbol: "line.3.horizontal.decrease") {
            Task { await store.setHistoryFilter(HistoryFilter(scope: .allBranches, hideMerges: store.historyFilter.hideMerges)) }
        })
        result.append(AppCommand(id: "history.toggleMerges", title: store.historyFilter.hideMerges ? "Show Merge Commits" : "Hide Merge Commits", subtitle: nil, group: "History", symbol: "arrow.triangle.merge") {
            Task { await store.setHistoryFilter(HistoryFilter(scope: store.historyFilter.scope, hideMerges: !store.historyFilter.hideMerges)) }
        })

        // Display
        result.append(AppCommand(id: "display.toggleDensity", title: "Toggle Compact Density", subtitle: AppPreferences.density.rawValue, group: "Display", symbol: "rectangle.compress.vertical") {
            AppPreferences.density = AppPreferences.density == .compact ? .comfortable : .compact
            NotificationCenter.default.post(name: .aviDensityChanged, object: nil)
        })

        return result
    }
}
