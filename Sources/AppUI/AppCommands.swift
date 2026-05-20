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
}
