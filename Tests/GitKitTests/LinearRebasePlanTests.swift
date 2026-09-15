@testable import GitKit
import Testing

struct LinearRebasePlanTests {
    private let base = String(repeating: "a", count: 40)
    private let first = String(repeating: "b", count: 40)
    private let second = String(repeating: "c", count: 40)
    private let head = String(repeating: "d", count: 40)

    @Test func rewordPreservesEveryDescendant() throws {
        let plan = try LinearRebasePlan(
            parentListing: "\(first) \(base)\n\(second) \(first)\n\(head) \(second)\n",
            oldest: first, target: first, verb: "reword"
        )
        #expect(plan.todo == "reword \(first)\npick \(second)\npick \(head)\n")
    }

    @Test func rangeEditKeepsCommitsAfterTarget() throws {
        let plan = try LinearRebasePlan(
            parentListing: "\(first) \(base)\n\(second) \(first)\n\(head) \(second)\n",
            oldest: first, target: second, verb: "edit"
        )
        #expect(plan.todo == "pick \(first)\nedit \(second)\npick \(head)\n")
    }

    @Test func rejectsMergeHistory() {
        #expect(throws: GitError.self) {
            try LinearRebasePlan(parentListing: "\(first) \(base) \(second)\n", oldest: first, target: first, verb: "edit")
        }
    }

    @Test func rejectsMissingTargetAndInjectedInstructions() {
        for target in [head, "\(first)\nexec unexpected", "HEAD"] {
            #expect(throws: GitError.self) {
                try LinearRebasePlan(parentListing: "\(first) \(base)\n", oldest: first, target: target, verb: "edit")
            }
        }
    }
}
