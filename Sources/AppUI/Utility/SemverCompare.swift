import Foundation
import GitKit

/// Best-effort semver parsing for tag-style names like `v1.2.3`, `v1.2.3-beta.1`, `2.0`.
/// Tags that don't parse fall through to localized standard ordering.
struct SemanticVersion: Equatable {
    let components: [Int]
    let prerelease: String?

    init?(_ raw: String) {
        var s = raw
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        guard !s.isEmpty, let firstChar = s.first, firstChar.isNumber else { return nil }

        let withoutBuild = s.split(separator: "+", maxSplits: 1).first.map(String.init) ?? s
        let parts = withoutBuild.split(separator: "-", maxSplits: 1)
        let core = parts[0]
        let pre = parts.count > 1 ? String(parts[1]) : nil

        let nums = core.split(separator: ".").compactMap { Int($0) }
        guard !nums.isEmpty, nums.count == core.split(separator: ".").count else { return nil }

        self.components = nums
        self.prerelease = pre
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        // Equal numeric core: prerelease is older than release (1.0.0-rc < 1.0.0).
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _?): return false
        case (_?, nil): return true
        case (let l?, let r?): return l < r
        }
    }
}

enum TagSort {
    /// Sort tags semver-descending; non-parseable tags fall to the bottom in reverse natural order.
    static func descending(_ refs: [GitReference]) -> [GitReference] {
        refs.sorted { lhs, rhs in
            let lv = SemanticVersion(lhs.name)
            let rv = SemanticVersion(rhs.name)
            switch (lv, rv) {
            case (let l?, let r?):
                return r < l
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            }
        }
    }
}
