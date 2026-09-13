#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

signing_identity="${COMPUTAH_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    if ! identity_report="$(security find-identity -v -p codesigning 2>/dev/null)"; then
        print -u2 -- "Could not inspect existing signing identities in Keychain. Set COMPUTAH_SIGNING_IDENTITY to an existing identity."
        exit 1
    fi
    signing_identity="$(print -r -- "$identity_report" | awk '/"Apple Development:/ { print $2; exit }')"
    if [[ -z "$signing_identity" ]]; then
        signing_identity="$(print -r -- "$identity_report" | awk '/"Developer ID Application:/ { print $2; exit }')"
    fi
    if [[ -z "$signing_identity" ]]; then
        print -u2 -- "No valid Apple Development or Developer ID signing identity found. Set COMPUTAH_SIGNING_IDENTITY to an existing identity."
        exit 1
    fi
fi
if [[ "$signing_identity" == "-" ]]; then
    print -u2 -- "Explicit ad hoc signing requested. macOS permission approvals may change after each rebuild."
fi

swift build -c release
mkdir -p dist
staging_directory="$(mktemp -d "$PWD/dist/.computah-build.XXXXXX")"
final_bundle="$PWD/dist/Computah.app"
staged_bundle="$staging_directory/Computah.app"
previous_bundle="$staging_directory/previous.app"
cleanup() {
    local result_code=$?
    if [[ ! -e "$final_bundle" && -d "$previous_bundle" ]]; then
        mv "$previous_bundle" "$final_bundle" || print -u2 -- "Could not restore the previous app bundle: $previous_bundle"
    fi
    if [[ -d "$previous_bundle" && ! -e "$final_bundle" ]]; then
        print -u2 -- "Previous app retained at $previous_bundle"
    else
        rm -r "$staging_directory"
    fi
    return "$result_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$staged_bundle/Contents/MacOS"
cp .build/release/Computah "$staged_bundle/Contents/MacOS/Computah"
cp Resources/Info.plist "$staged_bundle/Contents/Info.plist"
previous_version=0
if [[ -f "$final_bundle/Contents/Info.plist" ]]; then
    previous_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$final_bundle/Contents/Info.plist" 2>/dev/null || true)"
fi
if [[ "$previous_version" != <-> ]]; then previous_version=0; fi
build_version=$((10#${previous_version} + 1))
build_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
staged_info="$staged_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_version" "$staged_info"
if ! /usr/libexec/PlistBuddy -c "Set :ComputahBuildDate $build_date" "$staged_info" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :ComputahBuildDate string $build_date" "$staged_info"
fi
if ! codesign --force --sign "$signing_identity" --identifier com.lvl8.computah "$staged_bundle"; then
    print -u2 -- "Signing failed. Allow access to the existing signing key if macOS requests it, or choose an existing identity with COMPUTAH_SIGNING_IDENTITY. The previous app is unchanged."
    exit 1
fi
codesign --verify --strict "$staged_bundle"

# Publish only the complete, verified bundle. Never overwrite the running binary in place.
if [[ -e "$final_bundle" ]]; then mv "$final_bundle" "$previous_bundle"; fi
mv "$staged_bundle" "$final_bundle"
print -- "Built and signed dist/Computah.app, build $build_version ($build_date)"
