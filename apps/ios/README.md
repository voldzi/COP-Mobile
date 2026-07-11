# COP Mobile iOS host

SwiftUI/WKWebView feasibility host for iOS and iPadOS 26. The generated Xcode
project is intentionally not committed; `project.yml` is its source of truth.

```bash
cd apps/ios
xcodegen generate
xcodebuild \
  -project COPMobile.xcodeproj \
  -scheme COPMobile \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

The app loads the remote COP web in the persistent default WebKit data store.
Release navigation is limited to the exact COP and OIDC origins declared in
`Config/Info-Release.plist`. Debug additionally allows the explicit local COP
origin; Staging fails closed until its real origins are configured.

The only native Device API implemented in the feasibility phase is handshake
and the read-only `system.getCapabilities` snapshot. No permission prompt,
sensor, tracking, media, push or relay operation is implemented by this target.
