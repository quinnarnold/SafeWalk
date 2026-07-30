# iOS application

SafeWalk is an iOS 17+ SwiftUI application using Mapbox Maps and Navigation.

## Prerequisites

- Xcode 26.1; older Xcode versions are unverified
- An Apple Developer team for device and Release builds
- A Mapbox secret token with `Downloads:Read` in `~/.netrc`
- A running SafeWalk backend

Mapbox's package download credential is separate from the runtime token minted
by the backend. Never commit either token.

## Configure a fork

In the app and widget target build settings:

1. Set unique app and widget bundle identifiers.
2. Set `SAFEWALK_APP_GROUP` to an App Group owned by your team. The same value
   is substituted into both entitlements and both Info plists.
3. Set `SAFEWALK_API_BASE_URL` to the HTTPS URL of your backend for Release.
4. Optionally set `SAFEWALK_MAP_STYLE_URI`.
5. Enable App Attest for the app identifier and set the backend
   `APP_ATTEST_APP_ID` to `TEAMID.BUNDLEID`. Set
   `APP_ATTEST_BUNDLE_VERSION` to the app's `CFBundleVersion` and
   limit `APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES` to the distribution modes
   you use.

Debug builds default to `http://localhost:8080` and the shared Run scheme uses
Debug. Release builds have no live service default; if
`SAFEWALK_API_BASE_URL` is absent they use the reserved
`https://api.safewalk.invalid` address and fail closed.

## Build

Open `SafeWalk.xcodeproj` and run the `SafeWalk` scheme, or:

```bash
xcodebuild \
  -project SafeWalk.xcodeproj \
  -scheme SafeWalk \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Mapbox package resolution requires a valid downloads token even for simulator
builds. CI always parses all Swift and property-list files; the full build job
is enabled with `ENABLE_IOS_CI=true` and `MAPBOX_DOWNLOADS_TOKEN`.

## Privacy and release checks

The app sends route coordinates to the configured backend. Share My Walk
temporarily sends and stores live location. Review the root `PRIVACY.md`,
`SAFETY_AND_LIMITATIONS.md`, and both `PrivacyInfo.xcprivacy` files before
distributing a modified build.
