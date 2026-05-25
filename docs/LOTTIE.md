# Lottie animations

Avi can play [Lottie](https://lottiefiles.com/) animations through the
`LottieView` SwiftUI wrapper. When no JSON file is shipped for a given
animation name, the wrapper falls back to a stock `ProgressView`, so a
missing animation never blanks the UI.

## Where to drop files

```
Sources/AppUI/Resources/Lottie/<name>.json
```

The `AppUI` target declares `resources: [.process("Resources")]`, so any
JSON file dropped under `Resources/Lottie/` is bundled automatically.

## Names used today

| File name                | Used by                                | Loop |
| ------------------------ | -------------------------------------- | ---- |
| `downloading.json`       | `CloneSheet` progress step             | yes  |
| `empty-repo.json`        | `RepositoryPickerView` empty state     | yes  |

## Where to find animations

[lottiefiles.com](https://lottiefiles.com/) has thousands of free Lottie
files. Search keywords:

- **`downloading.json`**: "downloading", "syncing files", "cloud arrow"
- **`empty-repo.json`**: "empty box", "no data", "folder hello"

Pick something with a neutral palette - it'll inherit the app's tint
once we wire `ColorValueProvider` (future iteration).

## Adding more

1. Drop the JSON in `Sources/AppUI/Resources/Lottie/`.
2. Use it from a SwiftUI view: `LottieView(name: "my-animation")`.
3. Rebuild. No `Package.swift` change needed.

## Local build note

The bare-CLI `./build.sh` fallback path doesn't resolve SwiftPM
dependencies, so Lottie isn't linked locally - `LottieView` falls back
to the stock `ProgressView`. The full `swift build` (Xcode / CI) resolves
Lottie and plays the animations.
