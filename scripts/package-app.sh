#!/usr/bin/env bash
#
# Wrap the SwiftPM release executable in a minimal Avi.app bundle and zip it.
# Expects `swift build -c release` to have produced `.build/release/AviApp`.
#
# If the build produced dylibs (e.g., `libAppUI.dylib`, `libGitKit.dylib`) the
# script copies them into `Contents/Frameworks/` and rewrites the executable's
# rpath to `@executable_path/../Frameworks`. SwiftPM with static libraries
# produces no dylibs, in which case this step is a no-op.
#
# Usage: scripts/package-app.sh <version>

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: scripts/package-app.sh <version>" >&2
    exit 2
fi

VERSION="$1"
APP_NAME="Avi"
APP_DIR="dist/${APP_NAME}.app"
EXE="${APP_DIR}/Contents/MacOS/${APP_NAME}"
FRAMEWORKS="${APP_DIR}/Contents/Frameworks"
SRC_DIR=".build/release"
SRC_BIN="${SRC_DIR}/AviApp"
TEMPLATE="scripts/Info.plist.template"
ZIP="avi-${VERSION}-macos-arm64.zip"

cd "$(dirname "$0")/.."

if [[ ! -x "${SRC_BIN}" ]]; then
    echo "error: ${SRC_BIN} not found. Run 'swift build -c release --arch arm64' first." >&2
    exit 1
fi

if [[ ! -f "${TEMPLATE}" ]]; then
    echo "error: ${TEMPLATE} not found." >&2
    exit 1
fi

rm -rf dist
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${FRAMEWORKS}"

cp "${SRC_BIN}" "${EXE}"

# Copy any dylibs SwiftPM produced into Contents/Frameworks/ and point the
# executable at them via @executable_path/../Frameworks.
shopt -s nullglob
DYLIBS=( "${SRC_DIR}"/*.dylib )
shopt -u nullglob

NEED_FW_RPATH=0
if (( ${#DYLIBS[@]} > 0 )); then
    for dylib in "${DYLIBS[@]}"; do
        cp "${dylib}" "${FRAMEWORKS}/"
    done
    NEED_FW_RPATH=1
fi

# SwiftPM-resolved xcframeworks (Lottie etc.) land in the build dir as
# `<Name>.framework` next to the executable. Copy them into Contents/Frameworks
# so the bundle can dyld-load them at runtime.
shopt -s nullglob
FRAMEWORKS_SRC=( "${SRC_DIR}"/*.framework )
shopt -u nullglob

if (( ${#FRAMEWORKS_SRC[@]} > 0 )); then
    for fw in "${FRAMEWORKS_SRC[@]}"; do
        rm -rf "${FRAMEWORKS}/$(basename "${fw}")"
        cp -R "${fw}" "${FRAMEWORKS}/"
    done
    NEED_FW_RPATH=1
fi

if (( NEED_FW_RPATH )); then
    # Replace the @rpath the executable was built with (typically
    # @executable_path or @loader_path) so frameworks/dylibs resolve from
    # Frameworks/.
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${EXE}" || true
    # Some SwiftPM builds bake in an absolute rpath into .build; strip it so
    # the bundle is portable.
    BAD_RPATH="$(otool -l "${EXE}" | awk '/LC_RPATH/{found=1} found && /path /{print $2; exit}')"
    if [[ -n "${BAD_RPATH:-}" && "${BAD_RPATH}" == /* ]]; then
        install_name_tool -delete_rpath "${BAD_RPATH}" "${EXE}" || true
    fi
fi

# SwiftPM-generated resource bundles for the AppUI / dependency targets sit
# next to the executable as `<Pkg>_<Target>.bundle`. Carry them into
# Contents/Resources so Bundle.module lookups work at runtime.
shopt -s nullglob
RES_BUNDLES=( "${SRC_DIR}"/*.bundle )
shopt -u nullglob

for b in "${RES_BUNDLES[@]}"; do
    rm -rf "${APP_DIR}/Contents/Resources/$(basename "${b}")"
    cp -R "${b}" "${APP_DIR}/Contents/Resources/"
done

strip -x "${EXE}" 2>/dev/null || true

sed -e "s/__VERSION__/${VERSION}/g" "${TEMPLATE}" > "${APP_DIR}/Contents/Info.plist"

# App icon: copied into Contents/Resources/ to match CFBundleIconFile=AppIcon.
ICON_SRC="Branding/AppIcon.icns"
if [[ -f "${ICON_SRC}" ]]; then
    cp "${ICON_SRC}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
    echo "warning: ${ICON_SRC} not found; bundle will fall back to the default icon." >&2
fi

# In-app branding resources (wordmark used by the picker empty state and the
# custom About panel). Mirror the directory layout under Resources/.
if [[ -d "Sources/AppUI/Resources/Branding" ]]; then
    mkdir -p "${APP_DIR}/Contents/Resources/Branding"
    cp Sources/AppUI/Resources/Branding/*.png \
        "${APP_DIR}/Contents/Resources/Branding/" 2>/dev/null || true
fi

# Ad-hoc sign so macOS at least registers a stable code identity and the bundle
# launches cleanly on the local machine. Downloaders on other Macs still hit
# Gatekeeper unless they right-click -> Open the first time; that workaround is
# documented in README under "Releases".
codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --verbose=1 "${APP_DIR}" >/dev/null

# Strip extended attributes so `ditto` doesn't write `._X` Apple Double
# sidecars into the archive. Safe to call even when no xattrs are present.
xattr -cr "${APP_DIR}" 2>/dev/null || true

# Drop the empty Frameworks dir so the bundle stays tidy when nothing was copied.
if [[ -d "${FRAMEWORKS}" && -z "$(ls -A "${FRAMEWORKS}")" ]]; then
    rmdir "${FRAMEWORKS}"
fi

rm -f "${ZIP}"
# Use plain `zip` instead of `ditto` so the archive contains no `__MACOSX/`
# sidecars or `._*` Apple Double files. macOS extended attributes are
# already stripped above.
(cd dist && zip -qr -X "../${ZIP}" "${APP_NAME}.app")

echo "Built ${ZIP}"
ls -la "${ZIP}"
