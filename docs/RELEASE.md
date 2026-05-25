# Release checklist (local Mac build)

The end-to-end flow to cut a new Avi release without CI runners. Everything
runs on your Mac. Replace `<version>` with the new semver (for example
`0.1.0`).

Requirements:

- macOS 14+ with Xcode installed (full Xcode, not just Command Line Tools -
  the SwiftPM manifest links cleanly with full Xcode).
- `gh` CLI authenticated against the `mrcat71/avi` repo (`gh auth status`).
- A working `git` push remote.

No paid Apple Developer ID is required for v0.1.0: the bundle is ad-hoc
signed by `scripts/package-app.sh`. Downloaders on other Macs will hit
Gatekeeper the first time and must right-click -> Open the `.app`. The
README documents this.

## 1. Prepare the branch

1. Bump the version constant in `Sources/GitKit/GitKit.swift`:
   ```swift
   public static let version = "<version>"
   ```
2. Update the matching assertion in `Tests/GitKitTests/SmokeTests.swift`.
3. In `CHANGELOG.md`, move entries from `[Unreleased]` into a new
   `## [<version>] - YYYY-MM-DD` section.
4. Stage and commit:
   ```sh
   git add Sources/GitKit/GitKit.swift Tests/GitKitTests/SmokeTests.swift CHANGELOG.md
   git commit -m "chore: prepare v<version>"
   ```
5. Push the branch and open / merge a PR (skip if you're maintaining a
   tag-only flow on `main`).

## 2. Build the release artifacts locally

```sh
# Sanity check toolchain.
swift --version

# Release build of the executable.
swift build -c release --arch arm64

# Wrap into Avi.app, copy the icon + wordmark, ad-hoc sign, and zip.
scripts/package-app.sh <version>
```

`package-app.sh` writes:

- `dist/Avi.app`               - the bundle.
- `avi-<version>-macos-arm64.zip` - the distributable archive.

If `swift build -c release` fails on a stock-Command-Line-Tools toolchain
(no full Xcode), install Xcode from the App Store and rerun. The legacy
fallback `./build.sh` is debug-only and not suitable for releases.

Generate the checksum next to the zip:

```sh
shasum -a 256 avi-<version>-macos-arm64.zip > SHA256SUMS
```

## 3. Smoke-test the bundle

```sh
./dist/Avi.app/Contents/MacOS/Avi --version         # prints <version>
./dist/Avi.app/Contents/MacOS/Avi --self-test       # prints "ok"
open dist/Avi.app                                   # launches the GUI
```

In the GUI verify:

- The dock and Cmd-Tab show the Avi wordmark icon.
- Avi -> About Avi shows the wordmark as the panel icon and the version.
- The repository picker empty state shows the wordmark above the
  description.
- "Add existing" can open a local repo and the basic flows work.

## 4. Tag from main

Once the prep commit is merged into `main`:

```sh
git checkout main && git pull
git tag -a v<version> -m "v<version>"
git push origin v<version>
```

## 5. Publish the GitHub Release

Auto-generate notes from the tag and attach both artifacts:

```sh
gh release create v<version> \
  avi-<version>-macos-arm64.zip \
  SHA256SUMS \
  --title "v<version>" \
  --generate-notes
```

If you prefer hand-written notes, replace `--generate-notes` with
`--notes-file path/to/notes.md`.

## 6. Verify the release page

1. Browse to https://github.com/mrcat71/avi/releases/tag/v<version>.
2. Confirm `avi-<version>-macos-arm64.zip` and `SHA256SUMS` are attached.
3. On a clean machine: download both, run `shasum -a 256 -c SHA256SUMS`,
   unzip, right-click -> Open the `.app`, click Open in the Gatekeeper
   dialog. The app should launch.

## 7. Recover from a bad release

```sh
gh release delete v<version> --yes
git tag -d v<version>
git push --delete origin v<version>
```

Fix the underlying issue, restart from step 1.
