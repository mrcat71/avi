#!/usr/bin/env bash
# Swift Build's resource accessor searches Contents/Resources in an installed .app.
# The native SwiftPM accessor only searches the .app root and the build machine.
set -euo pipefail

cd "$(dirname "$0")/.."
exec swift build --build-system swiftbuild -c release --arch arm64 "$@"
