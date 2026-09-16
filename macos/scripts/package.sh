#!/usr/bin/env bash
#
# The one way a distributable Mochi is built (ADR-0014). CI's release workflow calls this exact
# script rather than reimplementing the steps, so a dmg built here and one attached to a GitHub
# Release differ only in which machine ran them.
#
# Usage:
#   scripts/package.sh
#
# Environment:
#   MOCHI_VERSION         Override the version instead of deriving it from the git tag on HEAD.
#                         Lets a maintainer rehearse a release build before the tag exists.
#   MOCHI_SIGN_IDENTITY   A "Developer ID Application: …" identity. Unset (the default, and always
#                         the case on CI) signs ad-hoc, which Gatekeeper will stop on first launch —
#                         see the install section of README.md.
#   MOCHI_NOTARY_PROFILE  A `notarytool store-credentials` keychain profile. Requires
#                         MOCHI_SIGN_IDENTITY: notarization only accepts Developer ID signatures.
#
# Both signing variables are wiring for the day a certificate exists; there is no certificate on
# this project today (ADR-0014 explains why, and why a self-signed one would buy nothing).

set -euo pipefail

# The repo's convention for script output (CLAUDE.md) is nothing while it works, one summary line
# when it's done: everything goes to the log, and only a failure puts any of it on screen.
run_quiet() {
    if ! "$@" >>"$log_file" 2>&1; then
        echo "package.sh: 失败于 $1，末尾输出如下（完整日志见 $log_file）" >&2
        tail -40 "$log_file" >&2
        exit 1
    fi
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
macos_dir=$(dirname "$script_dir")
build_dir="$macos_dir/.build/package"
dist_dir="$macos_dir/dist"
log_file="$build_dir/xcodebuild.log"

sign_identity="${MOCHI_SIGN_IDENTITY:-}"
notary_profile="${MOCHI_NOTARY_PROFILE:-}"

if [[ -n "$notary_profile" && -z "$sign_identity" ]]; then
    echo "package.sh: MOCHI_NOTARY_PROFILE 需要配合 MOCHI_SIGN_IDENTITY —— 公证只接受 Developer ID 签名的产物" >&2
    exit 1
fi

# The version comes from the tag on HEAD and nowhere else. A build off an untagged commit stamps no
# version at all, so the About panel falls back to "dev" (AppInfo.version) — the same thing
# `swift run Mochi` reports, and deliberately not a number that could be mistaken for a release.
#
# CFBundleVersion gets the same string rather than something like a commit count: a second derivation
# would be a second place a version number is decided, which is exactly what making the tag the only
# source of truth (ADR-0014) was for. Two builds can only share a CFBundleVersion by sharing a tag.
version="${MOCHI_VERSION:-}"
if [[ -z "$version" ]]; then
    version=$(git -C "$macos_dir" describe --tags --exact-match HEAD 2>/dev/null || true)
fi
# Tags are written `v0.1.0`; the version inside the bundle is not. Stripping here rather than at the
# tag lookup means an override can be spelled either way.
version="${version#v}"

label="${version:-dev}"
app_path="$build_dir/DerivedData/Build/Products/Release/Mochi.app"
dmg_path="$dist_dir/Mochi-$label.dmg"
staging_dir="$build_dir/dmg"

# dist is emptied, not just the same-named dmg: the release workflow picks the artifact up with a
# glob, so "one run leaves exactly one dmg" has to be true rather than merely usual.
rm -rf "$build_dir" "$dist_dir"
mkdir -p "$build_dir" "$dist_dir"

# Passing MARKETING_VERSION= empty is the same as leaving the project's own empty value alone, so
# the untagged case simply omits it.
build_args=(
    -project "$macos_dir/Mochi.xcodeproj"
    -scheme Mochi
    -configuration Release
    -destination 'platform=macOS,arch=arm64'
    -derivedDataPath "$build_dir/DerivedData"
)
if [[ -n "$version" ]]; then
    build_args+=(MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$version")
fi

run_quiet xcodebuild build "${build_args[@]}"

# xcodebuild has already signed the bundle, ad-hoc, from the project's CODE_SIGN_IDENTITY. Signing
# again here is what makes this script — rather than the project file — the place that decides how a
# distributed build is signed, and it is the seam the Developer ID branch hangs off.
if [[ -n "$sign_identity" ]]; then
    run_quiet codesign --force --sign "$sign_identity" --options runtime --timestamp \
        --preserve-metadata=entitlements "$app_path"
else
    run_quiet codesign --force --sign - --options runtime \
        --preserve-metadata=entitlements "$app_path"
fi
run_quiet codesign --verify --strict "$app_path"

# Deliberately bare: the app and a symlink to /Applications, no background image and no icon
# positions. Arranging those needs AppleScript driving Finder, which a headless CI runner cannot do
# (ADR-0014) — and a dmg that only builds on a desk is not the single source of truth this is.
rm -rf "$staging_dir"
mkdir -p "$staging_dir"
cp -R "$app_path" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

run_quiet hdiutil create \
    -volname "Mochi" \
    -srcfolder "$staging_dir" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    -quiet \
    "$dmg_path"

if [[ -n "$sign_identity" ]]; then
    run_quiet codesign --force --sign "$sign_identity" --timestamp "$dmg_path"
fi

# Deliberately not run_quiet: this waits minutes on Apple's service, and its progress is the only
# sign it hasn't wedged.
if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$dmg_path"
fi

signature=$([[ -n "$sign_identity" ]] && echo "Developer ID" || echo "ad-hoc")
echo "OK  $dmg_path  (版本 $label，$signature 签名)"
