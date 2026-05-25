import Foundation

public extension Notification.Name {
    static let aviOpenRepository = Notification.Name("avi.openRepository")
    static let aviRefreshRepository = Notification.Name("avi.refreshRepository")
    static let aviStageAll = Notification.Name("avi.stageAll")
    static let aviUnstageAll = Notification.Name("avi.unstageAll")
    static let aviCommit = Notification.Name("avi.commit")
    static let aviFetchRepository = Notification.Name("avi.fetchRepository")
    static let aviPullRepository = Notification.Name("avi.pullRepository")
    static let aviPushRepository = Notification.Name("avi.pushRepository")
    static let aviCreateBranch = Notification.Name("avi.createBranch")
    static let aviCreateTag = Notification.Name("avi.createTag")
    static let aviOpenCommandPalette = Notification.Name("avi.openCommandPalette")
    static let aviOpenBranchSwitcher = Notification.Name("avi.openBranchSwitcher")
    static let aviGoToLocalChanges = Notification.Name("avi.goToLocalChanges")
    static let aviGoToAllCommits = Notification.Name("avi.goToAllCommits")
    static let aviToggleHistoryScope = Notification.Name("avi.toggleHistoryScope")
    static let aviDensityChanged = Notification.Name("avi.densityChanged")
}
