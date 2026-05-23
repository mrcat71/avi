@testable import AppUI
import Testing

struct PromptRendererTests {
    @Test func substitutesAllKnownPlaceholders() {
        let context = PromptContext(
            stagedDiff: "diff --git a/x b/x",
            branch: "feature/x",
            files: ["x.swift", "y.swift"],
            repo: "avi",
            model: "gpt-4o",
            lowLimit: 50,
            highLimit: 72,
            guideLine: 72
        )
        let template = """
        repo=${repo}
        branch=${branch}
        files=${files}
        model=${model}
        low=${lowLimit}
        high=${highLimit}
        wrap=${guideLine}
        ---
        ${target}
        """
        let rendered = PromptRenderer.render(template: template, context: context)
        #expect(rendered.contains("repo=avi"))
        #expect(rendered.contains("branch=feature/x"))
        #expect(rendered.contains("files=x.swift\ny.swift"))
        #expect(rendered.contains("model=gpt-4o"))
        #expect(rendered.contains("low=50"))
        #expect(rendered.contains("high=72"))
        #expect(rendered.contains("wrap=72"))
        #expect(rendered.contains("diff --git a/x b/x"))
    }

    @Test func leavesUnknownPlaceholdersLiteral() {
        let context = PromptContext(
            stagedDiff: "",
            branch: "main",
            files: [],
            repo: "avi",
            model: "",
            lowLimit: 0,
            highLimit: 0,
            guideLine: 0
        )
        let rendered = PromptRenderer.render(template: "hello ${typo}", context: context)
        #expect(rendered == "hello ${typo}")
    }

    @Test func targetMirrorsStagedDiff() {
        let context = PromptContext(
            stagedDiff: "SOME_DIFF",
            branch: "",
            files: [],
            repo: "",
            model: "",
            lowLimit: 0,
            highLimit: 0,
            guideLine: 0
        )
        let rendered = PromptRenderer.render(template: "${target}", context: context)
        #expect(rendered == "SOME_DIFF")
    }
}
