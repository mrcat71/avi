import Foundation

/// Context the prompt template can reference via `${var}` placeholders.
public struct PromptContext {
    public let target: String // alias for stagedDiff
    public let stagedDiff: String
    public let branch: String
    public let files: String // newline-separated
    public let repo: String
    public let model: String
    public let lowLimit: Int
    public let highLimit: Int
    public let guideLine: Int
    public let existingMessage: String
    public let commitDiff: String
    /// What you asked the AI to change about planned commits.
    public let instructions: String
    /// Planned commits being revised, as JSON.
    public let plan: String

    public init(
        stagedDiff: String,
        branch: String,
        files: [String],
        repo: String,
        model: String,
        lowLimit: Int,
        highLimit: Int,
        guideLine: Int,
        existingMessage: String = "",
        commitDiff: String = "",
        instructions: String = "",
        plan: String = ""
    ) {
        target = stagedDiff
        self.stagedDiff = stagedDiff
        self.branch = branch
        self.files = files.joined(separator: "\n")
        self.repo = repo
        self.model = model
        self.lowLimit = lowLimit
        self.highLimit = highLimit
        self.guideLine = guideLine
        self.existingMessage = existingMessage
        self.commitDiff = commitDiff
        self.instructions = instructions
        self.plan = plan
    }
}

enum PromptRenderer {
    /// Substitute every `${name}` placeholder in `template` from `context`. Unknown
    /// placeholders are left literal so users can spot typos in their templates.
    static func render(template: String, context: PromptContext) -> String {
        let table: [String: String] = [
            "target": context.target,
            "staged_diff": context.stagedDiff,
            "branch": context.branch,
            "files": context.files,
            "repo": context.repo,
            "model": context.model,
            "lowLimit": "\(context.lowLimit)",
            "highLimit": "\(context.highLimit)",
            "guideLine": "\(context.guideLine)",
            "existing_message": context.existingMessage,
            "commit_diff": context.commitDiff,
            "instructions": context.instructions,
            "plan": context.plan
        ]
        // One pass over the template: substituted text is never scanned again,
        // so a diff that happens to contain "${plan}" stays as it is.
        var output = ""
        var rest = template[...]
        while let open = rest.range(of: "${") {
            output += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.firstIndex(of: "}") else {
                rest = rest[open.lowerBound...]
                break
            }
            let key = String(afterOpen[..<close])
            if let value = table[key] {
                output += value
            } else {
                output += rest[open.lowerBound ... close]
            }
            rest = afterOpen[afterOpen.index(after: close)...]
        }
        output += rest
        return output
    }
}
