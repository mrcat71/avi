# Release checklist

Avi ships through GitHub Releases as `avi-<version>-macos-arm64.zip` plus
`SHA256SUMS`. The bundle is ad-hoc signed, not notarized. Intel and Linux
artifacts are not currently produced.

The normal publishing path is `.github/workflows/release.yml`: pushing a
`v<version>` tag tests, builds, packages, and publishes that revision. Do not
also run `gh release create` manually. A tag push can publish even while the
separate branch CI workflow is failing, so complete the checks below first.

## 0.2.0 readiness (2026-09-14)

Local test and release-build validation passed in the user's normal Xcode
environment after the reword, graph lane-count, and test-hook isolation fixes:

- All 32 XCTest tests passed. Swift Testing reported a successful run of 113
  tests in 26 suites. Two snapshot tests remain skipped because their reference
  images are not committed.
- `swift build -c release --arch arm64` succeeded and
  `.build/release/AviApp --version` returned `0.2.0`. The assistant also verified
  the resulting binary's arm64 architecture and version.
- SwiftFormat 0.63.0 passed with 0/141 files requiring formatting; Swift syntax
  parsing and Git whitespace checks passed. Formatting rules are unchanged.
- The user reported that the UI looks correct. This does not replace testing
  the packaged and downloaded application.
- The user packaged `0.2.0`, verified its checksum and code signature, and
  confirmed the bundled executable reports `0.2.0`. That artifact predates the
  subsequent GONE badge alignment and narrow-sidebar fix.
- The user's `gh auth status` confirmed the active `mrcat71` account is
  authenticated. The invalid inactive account is not a blocker for that account.

Remaining release gates:

- Re-run tests and rebuild/package after the GONE badge fix, then regenerate
  and verify `SHA256SUMS`. The new `LocalBranchRowLayoutTests` passed in an
  isolated runner using the updated sidebar source and previously built
  dependencies. It checks 16 width, density, selection, and current-branch
  combinations. A separate SwiftUI render was visually inspected before and
  after the fix. This is not a full application test of the new revision.
- Include the final unstaged changes and all untracked regression test files,
  including `LocalBranchRowLayoutTests.swift`, in the reviewed
  release revision. Do not commit build output or old checksums.
- Verify branch CI for the exact release commit, remote tag/release availability,
  and the published assets. The agent's GitHub request failed with a connection
  error; it did not establish whether `v0.2.0` is available remotely.

The assistant did not change the index, commits, tags, or remote. No publication
has been performed. The in-process Git queue does not lock out external clients.

## Prepare and verify the complete revision

1. Update `Sources/GitKit/GitKit.swift`, the matching version assertion in
   `Tests/GitKitTests/SmokeTests.swift`, and `CHANGELOG.md`.
2. Inspect staged, unstaged, and untracked files. A version-only commit does
   not include uncommitted application changes. Include required new source
   files and tests; exclude local configuration, credentials, and build output.

   ```sh
   git status --short
   git diff HEAD --stat
   git diff HEAD -- Sources Tests README.md CHANGELOG.md docs
   git ls-files --others --exclude-standard
   git diff --check
   ```

3. On a Mac with full Xcode, run the same checks used by CI. All must pass.

   ```sh
   swiftformat --lint .
   swift test
   swift build -c release --arch arm64
   .build/release/AviApp --version
   ```

   The reported version must match the intended tag. The legacy `./build.sh`
   fallback and isolated component tests are not substitutes for a SwiftPM
   release build and the complete test suite. Some tests and `--self-test`
   access Avi's user configuration; use a disposable macOS account for an
   isolated release check.

4. Smoke-test packaging locally. The packaging script replaces `dist/` and
   the ZIP for this version, so preserve any earlier artifacts first.

   ```sh
   scripts/package-app.sh 0.2.0
   shasum -a 256 avi-0.2.0-macos-arm64.zip > SHA256SUMS
   shasum -a 256 -c SHA256SUMS
   codesign --verify --deep --strict --verbose=2 dist/Avi.app
   ./dist/Avi.app/Contents/MacOS/Avi --version
   open dist/Avi.app
   ```

   Check Changes and History, staged/unstaged diffs, horizontal scrolling,
   resizing with and without a selection, repository switching, and tag
   inspection. Test commit/stage/checkout operations only in a disposable
   repository. Confirm the version in About Avi and that local changes remain
   intact when a checkout is refused.

## Commit, then wait for branch CI

Stage only the reviewed release contents, including new implementation files
and tests. Review the final index before committing:

```sh
git diff --cached --check
git diff --cached --stat
git diff --cached
git commit -m "chore(release): prepare v0.2.0"
```

Push the reviewed branch through the normal merge process. For a release
commit already on `main`, the following changes the remote branch:

```sh
git push origin main
```

Wait for all `ci` jobs on that exact commit to pass before tagging. Check
GitHub access and existing releases; authentication or network failures are
not evidence that a version is unused.

```sh
gh auth status
gh run list --repo mrcat71/avi --workflow ci.yml --branch main --commit "$(git rev-parse HEAD)" --limit 5
gh release list --repo mrcat71/avi --limit 10
git status --short
git log -1 --oneline
git ls-remote --tags origin refs/tags/v0.2.0
```

Proceed only with a clean working tree, the reviewed commit on `main`, passing
CI for that commit, and no existing `v0.2.0` tag or release.

## Publish through the tag workflow

These commands create the local tag and push it. **The push triggers public
release creation and asset uploads.** Run them only after the checks above:

```sh
git tag -a v0.2.0 -m "v0.2.0"
git push origin v0.2.0
```

Watch the release run and confirm both assets are present:

```sh
gh run list --repo mrcat71/avi --workflow release.yml --limit 5
gh release view v0.2.0 --repo mrcat71/avi --json tagName,isDraft,isPrerelease,assets,url
```

Download the ZIP and `SHA256SUMS` from the release into a fresh directory,
verify `shasum -a 256 -c SHA256SUMS`, and launch the downloaded bundle on
another Mac. Local build success alone does not verify the published assets.

## Failed or incorrect releases

If a workflow fails before publication, inspect its logs and confirm whether
a release or assets were created before deciding how to retry. Do not create
a competing manual release while the workflow is running.

Published releases are immutable. Fix a bad release in a new patch version;
do not delete or move its tag, replace its assets, or reuse its version.
