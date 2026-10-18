#!/bin/sh
# Local artifacts only. No GitHub upload or release creation.
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"
./package-release.sh
version=$(tr -d '[:space:]' < VERSION)
dmg="dist/apple-fm-terminal-$version.dmg"
/usr/bin/hdiutil create -ov -srcfolder build/package -volname 'Apple FM Terminal Preview' -format UDZO "$dmg"
if [ -n "${APPLE_FM_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$APPLE_FM_SIGN_IDENTITY" --timestamp "$dmg"
  codesign --verify --strict "$dmg"
fi
if [ -n "${APPLE_FM_NOTARY_PROFILE:-}" ]; then
  [ -n "${APPLE_FM_SIGN_IDENTITY:-}" ] || { echo 'Notarization requires distribution signing first.' >&2; exit 1; }
  xcrun notarytool submit "$dmg" --keychain-profile "$APPLE_FM_NOTARY_PROFILE" --wait --output-format json > dist/notarization.json
  /usr/bin/plutil -extract status raw -o - dist/notarization.json | /usr/bin/grep -qx Accepted || { echo 'Notarization was not accepted; do not publish.' >&2; exit 1; }
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  spctl --assess --type open --context context:primary-signature -v "$dmg"
else
  echo 'LOCAL CANDIDATE: distribution signing/notarization still required before publication.'
fi
(cd dist && shasum -a 256 "apple-fm-terminal-$version.tar.gz" apple-fm-terminal.tar.gz install.sh "apple-fm-terminal-$version.dmg" > SHA256SUMS)
echo 'Artifacts prepared locally under dist/. Nothing published.'
