#!/bin/bash
# Builds Ductus as a universal app (Apple Silicon and Intel) and packages it
# for download: Ductus-<version>.zip, Ductus-<version>.dmg and SHA256SUMS.txt.
#
# The app is signed ad hoc (free, not Apple-verified) and not notarized, so
# macOS asks people to approve it once (System Settings, Privacy & Security,
# Open Anyway). See the README.
#
# Usage: scripts/package.sh [output folder]   (default: build)
# Colors: off with DUCTUS_NO_COLOR=1 or NO_COLOR=1, or when not in a terminal.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -t 1 && -z "${DUCTUS_NO_COLOR:-}" && -z "${NO_COLOR:-}" ]]; then
    red=$'\e[31m'; green=$'\e[32m'; yellow=$'\e[33m'; reset=$'\e[0m'
else
    red=""; green=""; yellow=""; reset=""
fi
step() { echo "$*"; }
ok() { echo "${green}$*${reset}"; }
warn() { echo "${yellow}$*${reset}"; }
fail() { echo "${red}$*${reset}" >&2; exit 1; }

out="${1:-build}"
derived="$out/DerivedData"
version=$(xcodebuild -project Ductus.xcodeproj -scheme Ductus -configuration Release -showBuildSettings 2>/dev/null \
    | awk '/ MARKETING_VERSION = / { print $3; exit }')
[[ -n "$version" ]] || fail "Could not read the version from the Xcode project"
name="Ductus-$version"

step "Building Ductus $version for Apple Silicon and Intel..."
mkdir -p "$out"
if ! xcodebuild -project Ductus.xcodeproj -scheme Ductus -configuration Release \
    -derivedDataPath "$derived" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    build > "$out/build.log" 2>&1; then
    tail -30 "$out/build.log" >&2
    fail "Build failed. Full log: $out/build.log"
fi
app="$derived/Build/Products/Release/Ductus.app"
[[ -d "$app" ]] || fail "Built app not found at $app"

archs=$(lipo -archs "$app/Contents/MacOS/Ductus")
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || fail "Not a universal binary (architectures: $archs)"
ok "Universal binary: $archs"

codesign --verify --deep --strict "$app" || fail "Code signature check failed"
ok "Signed ad hoc (not notarized)"

step "Packaging..."
rm -f "$out/$name.zip" "$out/$name.dmg" "$out/SHA256SUMS.txt"
# ditto keeps the app's symlinks, permissions and signature intact.
ditto -c -k --keepParent "$app" "$out/$name.zip"

# The disk image opens to the app next to a link to Applications, for drag-to-install.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Ductus.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Ductus $version" -srcfolder "$staging" -ov -format UDZO "$out/$name.dmg" \
    || fail "Could not create the disk image"

(cd "$out" && shasum -a 256 "$name.zip" "$name.dmg" > SHA256SUMS.txt)
ok "Done:"
for file in "$name.zip" "$name.dmg" SHA256SUMS.txt; do
    echo "  $out/$file ($(du -h "$out/$file" | cut -f1 | xargs))"
done
[[ "$(sw_vers -productVersion)" == *beta* ]] && warn "Built on a beta macOS; release builds should come from CI." || true
