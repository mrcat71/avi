#!/usr/bin/env bash
#
# Wrap the SwiftPM release executable in a minimal Avi.app bundle, then zip it
# (the archive Sparkle installs updates from) and put it on a disk image next
# to a link to /Applications (what people download to install Avi).
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
DMG="avi-${VERSION}-macos-arm64.dmg"
DMG_ROOT="dist/dmg"
DMG_LAYOUT="scripts/dmg/DS_Store"

cd "$(dirname "$0")/.."

if [[ ! -x "${SRC_BIN}" ]]; then
    echo "error: ${SRC_BIN} not found. Run 'swift build -c release --arch arm64' first." >&2
    exit 1
fi

if [[ ! -f "${TEMPLATE}" ]]; then
    echo "error: ${TEMPLATE} not found." >&2
    exit 1
fi

# A bundle without the real public EdDSA key could never verify an update, so
# everyone who installed it would have to download the next version by hand.
# Checked before dist/ is replaced.
PLACEHOLDERS="$(sed -e 's/__VERSION__//g' "${TEMPLATE}" | grep -oE '__[A-Z_]+__' | sort -u | tr '\n' ' ' || true)"
if [[ -n "${PLACEHOLDERS}" ]]; then
    echo "error: ${TEMPLATE} still has placeholders: ${PLACEHOLDERS}" >&2
    echo "Put the public key printed by Sparkle's generate_keys in SUPublicEDKey (see docs/RELEASE.md)." >&2
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
# next to the executable as `<Pkg>_<Target>.bundle`. These do NOT satisfy
# `Bundle.module`: its generated accessor only looks in `Bundle.main.bundleURL`
# (the .app root, where content cannot be sealed by the signature) before
# trapping on the build machine's absolute .build path. App code therefore
# reads its resources from Contents/Resources through `Bundle.main`; the
# bundles are carried along so dependency assets ship with the app.
shopt -s nullglob
RES_BUNDLES=( "${SRC_DIR}"/*.bundle )
shopt -u nullglob

for b in "${RES_BUNDLES[@]}"; do
    rm -rf "${APP_DIR}/Contents/Resources/$(basename "${b}")"
    cp -R "${b}" "${APP_DIR}/Contents/Resources/"
done

strip -x "${EXE}" 2>/dev/null || true

sed -e "s/__VERSION__/${VERSION}/g" "${TEMPLATE}" > "${APP_DIR}/Contents/Info.plist"
plutil -lint "${APP_DIR}/Contents/Info.plist" >/dev/null

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

# Lottie animations, resolved via Bundle.main at runtime (see LottieView).
shopt -s nullglob
LOTTIE_FILES=( Sources/AppUI/Resources/Lottie/*.json )
shopt -u nullglob

if (( ${#LOTTIE_FILES[@]} > 0 )); then
    mkdir -p "${APP_DIR}/Contents/Resources/Lottie"
    cp "${LOTTIE_FILES[@]}" "${APP_DIR}/Contents/Resources/Lottie/"
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

rm -f "${ZIP}" "${DMG}"
# Use plain `zip` instead of `ditto` so the archive contains no `__MACOSX/`
# sidecars or `._*` Apple Double files. macOS extended attributes are
# already stripped above. `-y` is required: without it zip follows symlinks,
# so the Versions/Current links of Lottie.framework and Sparkle.framework
# unpack as duplicate files and the downloaded bundle no longer verifies
# ("bundle format is ambiguous").
(cd dist && zip -qry -X "../${ZIP}" "${APP_NAME}.app")

# The disk image opens on Avi.app and a link to /Applications to drag it onto.
# The committed Finder layout puts them side by side (see docs/RELEASE.md).
mkdir -p "${DMG_ROOT}"
ditto "${APP_DIR}" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"
cp "${DMG_LAYOUT}" "${DMG_ROOT}/.DS_Store"
# hdiutil now and then fails with "Resource busy" or stalls waiting for its
# helper, so each attempt gets three minutes (it normally takes seconds).
for attempt in 1 2 3; do
    if perl -e 'alarm shift; exec @ARGV' 180 hdiutil create -quiet -volname "${APP_NAME}" \
        -srcfolder "${DMG_ROOT}" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "${DMG}"; then
        break
    fi
    if (( attempt == 3 )); then
        echo "error: hdiutil create failed three times." >&2
        exit 1
    fi
    echo "warning: hdiutil create failed (attempt ${attempt}); retrying." >&2
    sleep 5
done
hdiutil verify -quiet "${DMG}"
rm -rf "${DMG_ROOT}"

echo "Built ${ZIP} and ${DMG}"
ls -la "${ZIP}" "${DMG}"
