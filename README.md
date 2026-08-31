# MacCommandTab

MacCommandTab is an in-development native macOS window switcher built with AppKit and SwiftUI. It presents application windows in most-recently-used order, supports keyboard search and navigation, exposes the selected real window behind the panel, and can show one-shot or live ScreenCaptureKit previews while the switcher is open.

## Requirements

- macOS 14 or later
- Xcode 16 or later with the macOS SDK
- A Mac capable of running the selected macOS deployment target

The project has no third-party dependencies.

## Build

Open `MacCommandTab.xcodeproj` in Xcode and run the `MacCommandTab` scheme, or build from Terminal:

```sh
xcodebuild build \
  -project MacCommandTab.xcodeproj \
  -scheme MacCommandTab \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Run the test suite with:

```sh
xcodebuild test \
  -project MacCommandTab.xcodeproj \
  -scheme MacCommandTab \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

For normal local use, run the app from Xcode with development signing enabled so macOS can associate privacy permissions with a stable app identity.

Debug builds use a separate `com.maccommandtab.app.debug` identity and appear as **MacCommandTab Dev**. Production archives keep the canonical `com.maccommandtab.app` identity and install at `/Applications/MacCommandTab.app`. See [docs/RELEASE.md](docs/RELEASE.md) for signing, notarization, installation, and process-path verification.

## Permissions

MacCommandTab requests two macOS privacy permissions:

- **Accessibility** allows the app to discover, focus, raise, minimize, and activate windows. Exact window switching cannot work without it.
- **Screen Recording** allows ScreenCaptureKit to produce window previews. The switcher still operates without this permission, but window contents are unavailable.

Preview frames are processed locally by this app and are not uploaded or sent to a remote service. Thumbnail mode performs one fresh capture batch when the switcher opens and then stops. Live Preview mode runs capture streams only while the switcher is open. The latest valid images may remain in an in-memory cache for fast reopening.

### Development-build permission troubleshooting

macOS attaches Screen Recording and Accessibility approval to the running app's code-signing identity, not just its visible name. An unsigned/ad-hoc Xcode build receives a new identity when its executable changes, so a checked “MacCommandTab” row can belong to an older build or to the installed release.

Debug builds identify themselves as **MacCommandTab Dev**. In Settings, use **Allow Window Previews**, enable that exact build in System Settings, then choose **Relaunch to Finish**. If approval is still stale, **Reset & Request Again** resets only the current Debug bundle's Screen Recording entry. Configuring Xcode with a stable Apple Development signing certificate prevents permission churn between normal rebuilds.

## Known limitations

- Window discovery and activation are subject to macOS Accessibility behavior and the capabilities exposed by each application.
- Some minimized, hidden, protected, or full-screen windows may not provide a live thumbnail or may require macOS to change Spaces when activated.
- Screen Recording permission changes can require the app to be relaunched before macOS applies them consistently.
- Multi-display behavior follows the display containing the switcher; display topology changes close the active session so it can reopen with current geometry and scale.

## Development status

MacCommandTab is under active development. Core switching, search, preview-on-top behavior, adaptive layouts, and live previews are implemented, but broader hardware and application compatibility testing is ongoing.
