@testable import AppUI
import Foundation
import Testing

@MainActor
@Suite("Agent skills tip")
struct AgentSkillsTipTests {
    private func defaults() -> UserDefaults {
        let name = "avi-tip-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func freshInstallShowsTheTipUntilDismissed() {
        let store = defaults()
        let first = AgentSkillsTip(defaults: store, skillsInstalled: { false })
        first.noteLaunch(isFreshInstall: true)
        #expect(first.isShowing)

        // Quitting without an answer keeps it for the next launch.
        let second = AgentSkillsTip(defaults: store, skillsInstalled: { false })
        second.noteLaunch(isFreshInstall: false)
        #expect(second.isShowing)

        second.dismiss()
        let third = AgentSkillsTip(defaults: store, skillsInstalled: { false })
        third.noteLaunch(isFreshInstall: false)
        #expect(third.isShowing == false)
    }

    @Test func anUpdateNeverShowsIt() {
        let tip = AgentSkillsTip(defaults: defaults(), skillsInstalled: { false })
        tip.noteLaunch(isFreshInstall: false)
        #expect(tip.isShowing == false)
    }

    @Test func installingTheSkillsRetiresIt() {
        let store = defaults()
        var installed = false
        let tip = AgentSkillsTip(defaults: store, skillsInstalled: { installed })
        tip.noteLaunch(isFreshInstall: true)
        #expect(tip.isShowing)

        installed = true
        tip.refresh()
        #expect(tip.isShowing == false)
        // Removing the skills later does not bring it back.
        installed = false
        tip.refresh()
        #expect(tip.isShowing == false)
    }
}
