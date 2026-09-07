# COP Mobile iOS host

Standalone SwiftUI/WKWebView host for iOS and iPadOS 26. The generated Xcode
project is intentionally not committed; `project.yml` is its source of truth.
The approved build environment is Xcode 27.0 beta build `27A5228h` with iOS SDK
27.0. The deployment target remains iOS/iPadOS 26.0. Automatic signing uses
Team `LM6W548X36` and bundle ID `cz.zeleznalady.csm.messenger`.

The native chat is compiled from the COP Mobile-owned local Swift package at
`../../packages/CSMCommunicationKit`. The project must not reference the
historical `04 CSM messenger` checkout or its Git repository. Removing that
application does not affect generation, build, test or runtime of COP Mobile.

```bash
bash scripts/verify-apple-toolchain.sh
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

The host owns the secure web shell, native communications surface,
notifications and call presentation. COP web remains authoritative for map,
reporting, layers and AI workflows.
