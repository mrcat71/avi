#!/usr/bin/env bash
#
# Write appcast.xml, the update feed installed copies of Avi read from
# https://github.com/mrcat71/avi/releases/latest/download/appcast.xml, for the
# zip that scripts/package-app.sh built. The feed lists only this release:
# every GitHub release carries its own, and "latest" points at the newest.
#
# Sparkle's generate_appcast signs the zip and the feed with the private EdDSA
# key read from SPARKLE_ED_PRIVATE_KEY (the release workflow's secret) or,
# outside CI, from the login Keychain where `generate_keys --account avi` put
# it. Release notes come from this version's section in CHANGELOG.md.
#
# Usage: [SPARKLE_ED_PRIVATE_KEY=<base64 key>] scripts/make-appcast.sh <version>

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: [SPARKLE_ED_PRIVATE_KEY=<base64 key>] scripts/make-appcast.sh <version>" >&2
    exit 2
fi

VERSION="$1"
ZIP="avi-${VERSION}-macos-arm64.zip"
STAGE="dist/appcast"
NOTES="${STAGE}/${ZIP%.zip}.md"
TOOLS=".build/artifacts/sparkle/Sparkle/bin"
KEYCHAIN_ACCOUNT="avi"
REPO_URL="https://github.com/mrcat71/avi"

cd "$(dirname "$0")/.."

if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" && -n "${CI:-}" ]]; then
    echo "error: SPARKLE_ED_PRIVATE_KEY is not set. Add it as a repository secret (see docs/RELEASE.md)." >&2
    exit 1
fi
if [[ ! -f "${ZIP}" ]]; then
    echo "error: ${ZIP} not found. Run scripts/package-app.sh ${VERSION} first." >&2
    exit 1
fi
if [[ ! -x "${TOOLS}/generate_appcast" ]]; then
    echo "error: ${TOOLS}/generate_appcast not found. Run 'swift package resolve' first." >&2
    exit 1
fi

rm -rf "${STAGE}" appcast.xml
mkdir -p "${STAGE}"
cp "${ZIP}" "${STAGE}/"

# generate_appcast embeds a .md file named after the archive as the notes.
awk -v version="${VERSION}" '
    index($0, "## [" version "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md > "${NOTES}"
if ! grep -q '[^[:space:]]' "${NOTES}"; then
    if [[ "${VERSION}" == *-dev.* ]]; then
        # Dry runs from workflow_dispatch have no changelog section.
        rm -f "${NOTES}"
    else
        echo "error: CHANGELOG.md has no notes under '## [${VERSION}]'." >&2
        exit 1
    fi
fi

FEED_ARGS=(
    --download-url-prefix "${REPO_URL}/releases/download/v${VERSION}/"
    --embed-release-notes
    --full-release-notes-url "${REPO_URL}/blob/main/CHANGELOG.md"
    --link "${REPO_URL}"
    -o appcast.xml
    "${STAGE}"
)
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    printf '%s' "${SPARKLE_ED_PRIVATE_KEY}" | "${TOOLS}/generate_appcast" --ed-key-file - "${FEED_ARGS[@]}"
else
    "${TOOLS}/generate_appcast" --account "${KEYCHAIN_ACCOUNT}" "${FEED_ARGS[@]}"
fi

# generate_appcast only warns, and leaves the update unsigned, when it finds
# no key or the key does not match SUPublicEDKey in the app. Every installed
# copy would refuse that update, so stop here instead of publishing it.
if ! grep -q 'sparkle:edSignature=' appcast.xml; then
    echo "error: the update in appcast.xml is not signed: the private key is missing or does not match SUPublicEDKey in scripts/Info.plist.template." >&2
    exit 1
fi
if ! grep -q "<sparkle:version>${VERSION}</sparkle:version>" appcast.xml; then
    echo "error: appcast.xml does not offer version ${VERSION}." >&2
    exit 1
fi
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    printf '%s' "${SPARKLE_ED_PRIVATE_KEY}" | "${TOOLS}/sign_update" --verify --ed-key-file - appcast.xml
else
    "${TOOLS}/sign_update" --verify --account "${KEYCHAIN_ACCOUNT}" appcast.xml
fi

echo "Wrote appcast.xml for ${VERSION}"
