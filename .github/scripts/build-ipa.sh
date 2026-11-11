#!/usr/bin/env bash
# Build a single-target, ad-hoc signed GestaltX-AI development IPA.
# No share extension, third-party signing service, release publishing or deployment.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/build/ipa}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
cd "$root"

version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);/\1/p' GestaltX.xcodeproj/project.pbxproj | sort -u)"
if [[ -z "$version" || "$(wc -l <<< "$version")" -ne 1 ]]; then
  echo "Expected exactly one marketing version" >&2
  exit 1
fi

xcodebuild -quiet -project GestaltX.xcodeproj -target GestaltX \
  -configuration Release -sdk iphoneos SYMROOT="$root/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload"
cp -R "$root/build/Release-iphoneos/GestaltX.app" "$stage/Payload/"
app="$stage/Payload/GestaltX.app"

# Preserve App Group metadata for a user's locally re-signed copy.
codesign -f -s - --entitlements GestaltX/GestaltX.entitlements "$app"
codesign --verify --strict "$app"
python3 - "$app" <<'VERIFY'
import plistlib, subprocess, sys
bundle = sys.argv[1]
response = subprocess.run(
    ["codesign", "-d", "--entitlements", "-", "--xml", bundle],
    capture_output=True, check=True
)
entitlements = plistlib.loads(response.stdout)
groups = entitlements.get("com.apple.security.application-groups")
if groups != ["group.com.gobiologycn.gestaltxai"]:
    raise SystemExit(f"Unexpected signed App Group entitlement: {groups!r}")
print("Verified standalone app signature and isolated App Group.")
VERIFY

ipa="$out/GestaltX-AI_$version-UNVERIFIED-DEVICE.ipa"
(cd "$stage" && zip -qry "$ipa" Payload)
printf 'Built development IPA: %s\n' "$ipa"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  { printf 'version=%s\n' "$version"; printf 'ipa=%s\n' "$ipa"; } >> "$GITHUB_OUTPUT"
fi
