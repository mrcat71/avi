import Foundation
@testable import GitKit

enum Fixtures {
    static func clean(branch: String = "main", upstream: String? = "origin/main") -> FakeGitProvider {
        FakeGitProvider(
            status: WorkingCopyStatus(
                branch: BranchInfo(name: branch, oid: "aaa1", upstream: upstream, ahead: 0, behind: 0),
                entries: []
            ),
            refs: RepositoryRefs(
                localBranches: [
                    GitReference(name: branch, fullName: "refs/heads/\(branch)", oid: "aaa1", kind: .localBranch,
                                 upstream: upstream, isCurrent: true)
                ],
                remoteBranches: upstream.map { up in [
                    GitReference(name: up, fullName: "refs/remotes/\(up)", oid: "aaa1", kind: .remoteBranch)
                ] } ?? [],
                tags: []
            ),
            commits: linearCommits(count: 5),
            remotes: [GitRemote(name: "origin", fetchURL: "git@example.com:org/repo.git", pushURL: "git@example.com:org/repo.git")]
        )
    }

    static func dirty() -> FakeGitProvider {
        let provider = clean()
        provider.status = WorkingCopyStatus(
            branch: provider.status.branch,
            entries: [
                FileStatus(path: "README.md", index: .unmodified, worktree: .modified),
                FileStatus(path: "Sources/Foo.swift", index: .added, worktree: .modified),
                FileStatus(path: "Sources/Bar.swift", index: .unmodified, worktree: .untracked),
                FileStatus(path: "LICENSE", index: .modified, worktree: .unmodified)
            ]
        )
        return provider
    }

    static func multibranch() -> FakeGitProvider {
        FakeGitProvider(
            status: WorkingCopyStatus(
                branch: BranchInfo(name: "main", oid: "m3", upstream: "origin/main", ahead: 2, behind: 1),
                entries: []
            ),
            refs: RepositoryRefs(
                localBranches: [
                    GitReference(name: "main", fullName: "refs/heads/main", oid: "m3", kind: .localBranch,
                                 upstream: "origin/main", isCurrent: true, ahead: 2, behind: 1),
                    GitReference(name: "feature/auth", fullName: "refs/heads/feature/auth", oid: "f3", kind: .localBranch,
                                 upstream: "origin/feature/auth", ahead: 5),
                    GitReference(name: "hotfix", fullName: "refs/heads/hotfix", oid: "h1", kind: .localBranch,
                                 upstream: nil)
                ],
                remoteBranches: [
                    GitReference(name: "origin/main", fullName: "refs/remotes/origin/main", oid: "m2", kind: .remoteBranch),
                    GitReference(name: "origin/feature/auth", fullName: "refs/remotes/origin/feature/auth", oid: "f1", kind: .remoteBranch)
                ],
                tags: [
                    GitReference(name: "v0.1.0", fullName: "refs/tags/v0.1.0", oid: "m1", kind: .tag),
                    GitReference(name: "v1.0.0", fullName: "refs/tags/v1.0.0", oid: "m2", kind: .tag,
                                 taggerDate: Date(timeIntervalSince1970: 1_700_000_000),
                                 annotatedMessage: "First major release")
                ]
            ),
            commits: [
                commit("m3", subject: "Refactor authentication module", parents: ["m2", "f3"]),
                commit("m2", subject: "Bump version to 1.0.0", parents: ["m1"]),
                commit("f3", subject: "Add OAuth provider", parents: ["f2"]),
                commit("f2", subject: "Wire login form", parents: ["f1"]),
                commit("f1", subject: "Scaffold auth module", parents: ["m1"]),
                commit("m1", subject: "Initial commit", parents: [])
            ],
            remotes: [GitRemote(name: "origin", fetchURL: "git@example.com:org/repo.git", pushURL: "git@example.com:org/repo.git")]
        )
    }

    private static func linearCommits(count: Int) -> [CommitSummary] {
        (0 ..< count).reversed().map { i in
            commit("c\(i)", subject: "commit \(i)", parents: i == 0 ? [] : ["c\(i - 1)"])
        }
    }

    private static func commit(_ oid: String, subject: String, parents: [String]) -> CommitSummary {
        CommitSummary(
            oid: oid,
            parentOIDs: parents,
            authorName: "Avi Test",
            authorEmail: "test@example.com",
            authorDate: Date(timeIntervalSince1970: 1_700_000_000),
            subject: subject,
            body: ""
        )
    }
}
