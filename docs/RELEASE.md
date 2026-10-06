# Release checklist

Avi ships through GitHub Releases as `avi-<version>-macos-arm64.dmg` (what
people download), `avi-<version>-macos-arm64.zip` (what in-app updates
install), `appcast.xml` (the signed Sparkle feed installed copies read from
`releases/latest/download/appcast.xml`), and `SHA256SUMS`. The bundle is
ad-hoc signed, not notarized. Intel and Linux artifacts are not currently
produced.

The normal publishing path is `.github/workflows/release.yml`: pushing a
`v<version>` tag tests, builds, packages, and publishes that revision. Do not
also run `gh release create` manually. A tag push can publish even while the
separate branch CI workflow is failing, so complete the checks below first.

## One-time setup: the update signing key

Installed copies of Avi accept an update only when it is signed with the
EdDSA key whose public half is `SUPublicEDKey` in
`scripts/Info.plist.template`. Ad-hoc code signatures change with every build,
so this key is the only link between versions: if it is lost, or replaced by a
new one, everyone has to install the next version by hand from the disk image.

1. Generate the key once. The private key stays in your login Keychain under
   the account `avi`; the command prints the public key.

   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account avi
   ```

2. Put the printed public key in `SUPublicEDKey` in
   `scripts/Info.plist.template` and commit it; the current key went in with
   0.7.1. `scripts/package-app.sh` refuses to build while the template still
   has a `__PLACEHOLDER__`.
3. Export the private key into a private temporary folder, store it as the
   release workflow's secret, and delete the export, even when a step fails.
   macOS may ask to allow access to the key. **`gh secret set` changes the
   repository's settings.**

   ```sh
   K="$(mktemp -d)/avi-sparkle.key" && .build/artifacts/sparkle/Sparkle/bin/generate_keys --account avi -x "$K" && gh secret set SPARKLE_ED_PRIVATE_KEY --repo mrcat71/avi < "$K"; rm -f "$K"
   ```

4. Keep a backup of the private key outside this Mac, such as in a password
   manager (`generate_keys --account avi -x <file>` exports it again; on
   another Mac, `generate_keys --account avi -f <file>` imports it). Never
   commit it.

## Prepare and verify the complete revision

1. Pick the version. Avi follows Semantic Versioning: a release with only
   **Fixed** entries is a patch (`0.4.2` to `0.4.3`); anything under **Added**
   or **Changed** is a minor (`0.4.2` to `0.5.0`). A version whose tag was
   already pushed is taken even without a release: reuse it only by moving the
   tag as in [Tag pushed before the version bump](#tag-pushed-before-the-version-bump),
   otherwise skip it. A skipped version gets no changelog section.
2. Bump the version in all five places. The release workflow fails when the
   tag and `GitKit.version` differ and `swift test` fails when the smoke test
   disagrees, but the other three files go stale silently. Before editing,
   note the current version:

   ```sh
   OLD=$(sed -n 's/.*version = "\(.*\)"/\1/p' Sources/GitKit/GitKit.swift)
   ```

   | File | Change |
   | ---- | ------ |
   | `Sources/GitKit/GitKit.swift` | `public static let version = "X.Y.Z"` |
   | `Tests/GitKitTests/SmokeTests.swift` | `#expect(GitKit.version == "X.Y.Z")` |
   | `CHANGELOG.md` | Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a new, empty `## [Unreleased]` above it. After a skipped version, start the section with a line such as "0.4.1 was tagged but never published, so its fixes ship in this release." |
   | `README.md` | `The current release is vX.Y.Z.` |
   | `docs/AGENT-INTEGRATION.md` | `"version":"X.Y.Z"` in the sample `avi propose` response |

   The bundle's `Info.plist` version comes from the argument to
   `scripts/package-app.sh`. After the bump this must print nothing:

   ```sh
   grep -rn -F "$OLD" --exclude-dir=.build --exclude-dir=dist --exclude-dir=.git --exclude='*.zip' --exclude=SHA256SUMS --exclude=CHANGELOG.md --exclude=RELEASE.md .
   ```

3. Inspect staged, unstaged, and untracked files. A version-only commit does
   not include uncommitted application changes. Include required new source
   files and tests; exclude local configuration, credentials, and build output.

   ```sh
   git status --short
   git diff HEAD --stat
   git diff HEAD -- Sources Tests README.md CHANGELOG.md docs
   git ls-files --others --exclude-standard
   git diff --check
   ```

4. On a Mac with full Xcode, run the same checks used by CI. All must pass.

   ```sh
   swiftformat --lint .
   swift test
   swift build -c release --arch arm64
   .build/release/AviApp --version
   .build/release/AviApp --self-test
   ```

   The reported version must match the intended tag. `--self-test` runs the
   AI preflight in the release binary, where a miscompiled async sleep aborts
   it (0.4.0 shipped with one). Branch CI runs it with its own toolchain, and
   the release workflow runs it on the packaged app before publishing. The
   legacy `./build.sh` fallback and isolated component tests are not
   substitutes for a SwiftPM release build and the complete test suite. Some tests and `--self-test`
   access Avi's user configuration; use a disposable macOS account for an
   isolated release check.

5. Smoke-test packaging locally. The packaging script replaces `dist/`, the
   ZIP, and the DMG for this version, so preserve any earlier artifacts first.
   `make-appcast.sh` signs with the key in your Keychain (macOS asks to allow
   access) and fails unless it matches `SUPublicEDKey`.

   ```sh
   scripts/package-app.sh 0.2.0
   shasum -a 256 avi-0.2.0-macos-arm64.dmg avi-0.2.0-macos-arm64.zip > SHA256SUMS
   shasum -a 256 -c SHA256SUMS
   codesign --verify --deep --strict --verbose=2 dist/Avi.app
   ./dist/Avi.app/Contents/MacOS/Avi --version
   ./dist/Avi.app/Contents/MacOS/Avi --self-test
   ./dist/Avi.app/Contents/MacOS/Avi --cli version
   scripts/make-appcast.sh 0.2.0
   open avi-0.2.0-macos-arm64.dmg
   open dist/Avi.app
   ./dist/Avi.app/Contents/MacOS/Avi --cli status
   ```

   The disk image must open on Avi and Applications side by side; the layout
   comes from `scripts/dmg/DS_Store` (to change it, arrange a writable copy of
   the image in Finder and copy that volume's `.DS_Store` back). `appcast.xml`
   must offer the new version with the CHANGELOG section as its notes.

   Check Changes and History, staged/unstaged diffs, horizontal scrolling,
   resizing with and without a selection, repository switching, and tag
   inspection. Once Avi is open, `--cli status` must report the new version,
   and in a disposable repository you opened in Avi, a `--cli propose` with two
   commits must land as planned commits in Changes. Test commit/stage/checkout
   operations only in a disposable repository. Confirm the version in About Avi
   and that local changes remain intact when a checkout is refused.

## Commit, then wait for branch CI

Stage only the reviewed release contents, including new implementation files
and tests. Review the final index before committing:

```sh
git diff --cached --check
git diff --cached --stat
git diff --cached
git commit -m "chore(release): prepare Avi 0.2.0"
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

When `SPARKLE_ED_PRIVATE_KEY` was just set or changed, prove it matches the
committed public key with a dry run of the release workflow first. It builds
and signs everything but publishes nothing; its `Generate signed appcast` step
fails on a mismatch. **This starts a workflow run on GitHub.**

```sh
gh workflow run release.yml --repo mrcat71/avi --ref main -f dry_run=true
gh run list --repo mrcat71/avi --workflow release.yml --limit 1
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

Watch the release run and confirm all four assets are present (DMG, ZIP,
`appcast.xml`, `SHA256SUMS`), then that the feed installed copies read now
offers the new version:

```sh
gh run list --repo mrcat71/avi --workflow release.yml --limit 5
gh release view v0.2.0 --repo mrcat71/avi --json tagName,isDraft,isPrerelease,assets,url
curl -sL https://github.com/mrcat71/avi/releases/latest/download/appcast.xml | grep '<sparkle:version>'
```

Download the DMG, the ZIP, and `SHA256SUMS` from the release into a fresh
directory, verify `shasum -a 256 -c SHA256SUMS`, and install from the DMG on
another Mac. On a Mac running the previous version (0.7.1 or later), **Avi >
Check for Updates…** must offer and install the new one. Local build success
alone does not verify the published assets.

## Failed or incorrect releases

If a workflow fails before publication, inspect its logs and confirm whether
a release or assets were created before deciding how to retry. Do not create
a competing manual release while the workflow is running.

### Tag pushed before the version bump

`Verify in-app version matches tag` fails when `GitKit.version` still holds the
previous version. That gate runs before the build, so nothing is packaged and no
release is created: the tag is unused and may be moved instead of burned. Bump
the version as in step 2, rerun the checks in step 4, commit, push `main`, and
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
