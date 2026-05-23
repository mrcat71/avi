# Release checklist

The steps a maintainer takes to cut a new Avi release. Replace `<version>`
with the new semver (for example `0.1.0`).

## 1. Prepare the branch

1. Bump the version constant in `Sources/GitKit/GitKit.swift`:
   ```swift
   public static let version = "<version>"
   ```
2. Update the matching assertion in `Tests/GitKitTests/SmokeTests.swift`.
3. Move CHANGELOG entries from `[Unreleased]` into a new
   `## [<version>] - YYYY-MM-DD` section.
4. Commit:
   ```sh
   git commit -am "chore: prepare v<version>"
   ```
5. Open a PR. CI (`build-test`, `lint`, `bundle-smoke`) must pass.

## 2. Tag from main

1. Merge the prep PR.
2. Pull `main` and create an annotated tag:
   ```sh
   git checkout main && git pull
   git tag -a v<version> -m "v<version>"
   git push origin v<version>
   ```

## 3. Watch the release workflow

`release.yml` runs on tag push and performs:

1. Tag version is parsed from `${GITHUB_REF}`.
2. `GitKit.version` is grepped from source and must match the tag.
3. A duplicate-release check via `gh release view` aborts if the tag was
   already released.
4. `swift test` runs before any packaging.
5. `swift build -c release --arch arm64`.
6. `scripts/package-app.sh <version>` assembles `dist/Avi.app` with the
   right `CFBundleShortVersionString`, then zips it.
7. `SHA256SUMS` is generated.
8. `gh release create` publishes the release with auto-generated notes and
   the zip + checksum attached.

## 4. Verify the release

1. Browse to the GitHub Release page; confirm
   `avi-<version>-macos-arm64.zip` and `SHA256SUMS` are attached.
2. Download both files to a clean directory.
3. Run `shasum -a 256 -c SHA256SUMS` and confirm OK.
4. Unzip `Avi.app` and double-click. Verify:
   - The app launches; the picker shows the empty state.
   - "Add existing" can open a local repo.
   - Commit panel, history view, and Settings all behave.
   - `./Avi.app/Contents/MacOS/Avi --version` prints `<version>`.

## 5. Recover from a bad release

1. Delete the GitHub Release (Release page → Delete).
2. Delete the tag locally and remotely:
   ```sh
   git tag -d v<version>
   git push --delete origin v<version>
   ```
3. Fix the underlying issue with a follow-up commit, then restart from
   step 2 with the same or bumped version.

## 6. Manual dispatch (test builds)

The `release.yml` workflow also accepts a `workflow_dispatch` event with a
`dry_run` input. Triggering it from the Actions tab builds the artifacts and
uploads them as workflow artifacts (`retention-days: 14`) without creating a
GitHub Release. Useful for verifying the packaging script before tagging.
