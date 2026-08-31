# Release workflow

MacCommandTab's canonical production identity is `com.maccommandtab.app`, installed at `/Applications/MacCommandTab.app`. Debug builds use `com.maccommandtab.app.debug` and display as **MacCommandTab Dev**, so running from Xcode does not silently replace or share privacy state with the installed release.

## Prerequisites

- A valid **Developer ID Application** certificate in the login keychain.
- The Apple Developer team ID that owns `com.maccommandtab.app`.
- Notary credentials stored once with `xcrun notarytool store-credentials MacCommandTabNotary`.
- A clean checkout or a reviewed worktree. Release archives must not be created from unreviewed local changes.

## Version and validate

Update the public version and increment the build number:

```sh
xcrun agvtool new-marketing-version 0.3.0
xcrun agvtool next-version -all
xcodebuild test \
  -project MacCommandTab.xcodeproj \
  -scheme MacCommandTab \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Complete [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md) on the signed candidate.

## Archive and sign

Replace the placeholders with the release team and certificate name:

```sh
xcodebuild archive \
  -project MacCommandTab.xcodeproj \
  -scheme MacCommandTab \
  -configuration Release \
  -archivePath "$PWD/build/MacCommandTab.xcarchive" \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  CODE_SIGN_IDENTITY='Developer ID Application: Your Company (YOUR_TEAM_ID)'
```

Export the Developer ID archive from Xcode Organizer. Confirm that Hardened Runtime is enabled and the exported app reports the production identity:

```sh
codesign --verify --deep --strict --verbose=2 build/export/MacCommandTab.app
codesign -dv --verbose=4 build/export/MacCommandTab.app 2>&1
```

## Notarize and staple

```sh
ditto -c -k --keepParent build/export/MacCommandTab.app build/MacCommandTab.zip
xcrun notarytool submit build/MacCommandTab.zip \
  --keychain-profile MacCommandTabNotary \
  --wait
xcrun stapler staple build/export/MacCommandTab.app
xcrun stapler validate build/export/MacCommandTab.app
spctl --assess --type execute --verbose=2 build/export/MacCommandTab.app
```

Do not distribute a candidate until notarization, stapling, signature verification, and Gatekeeper assessment all succeed.

## Install the canonical release

Quit every running production copy before replacing the exact application bundle:

```sh
osascript -e 'tell application id "com.maccommandtab.app" to quit' 2>/dev/null || true
pkill -x MacCommandTab 2>/dev/null || true
sudo rm -rf /Applications/MacCommandTab.app
sudo ditto build/export/MacCommandTab.app /Applications/MacCommandTab.app
open /Applications/MacCommandTab.app
```

The removal command above targets only `/Applications/MacCommandTab.app`; it does not remove preferences or permission records. Verify that the launched process is the canonical copy:

```sh
APP_PID="$(pgrep -x MacCommandTab | head -n 1)"
ps -p "$APP_PID" -o pid=,command=
```

The command path must begin with `/Applications/MacCommandTab.app/Contents/MacOS/MacCommandTab`. Remove old copies from Downloads or other folders before final QA so Launch Services cannot select an unintended build.
