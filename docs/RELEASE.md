# Release checklist

Avi ships through GitHub Releases as `avi-<version>-macos-arm64.zip` plus
`SHA256SUMS`. The bundle is ad-hoc signed, not notarized. Intel and Linux
artifacts are not currently produced.

The normal publishing path is `.github/workflows/release.yml`: pushing a
`v<version>` tag tests, builds, packages, and publishes that revision. Do not
also run `gh release create` manually. A tag push can publish even while the
separate branch CI workflow is failing, so complete the checks below first.

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

### Tag pushed before the version bump

`Verify in-app version matches tag` fails when `GitKit.version` still holds the
previous version. That gate runs before the build, so nothing is packaged and no
release is created: the tag is unused and may be moved instead of burned. Update
the three files from step 1, rerun the checks in step 3, commit, push `main`, and
move the tag onto the release commit:

```sh
git tag -f -a v0.3.0 -m "v0.3.0"
git push origin main
git push --force origin v0.3.0
```

Moving a tag is safe only while no release exists for it. Confirm with
`gh release view v0.3.0 --repo mrcat71/avi` first. If a release is already
published, leave that tag alone and ship the next version instead.

Published releases are immutable. Fix a bad release in a new patch version;
do not delete or move its tag, replace its assets, or reuse its version.
