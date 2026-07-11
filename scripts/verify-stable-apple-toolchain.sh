#!/usr/bin/env bash
set -euo pipefail

xcode_version="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
xcode_build="$(xcodebuild -version | sed -n '2s/^Build version //p')"
ios_sdk="$(xcrun --sdk iphoneos --show-sdk-version)"

if [[ ! "$xcode_version" =~ ^26\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "FAIL: release CI requires stable Xcode 26.x; selected Xcode is $xcode_version ($xcode_build)." >&2
  exit 1
fi
if [[ ! "$ios_sdk" =~ ^26\.[0-9]+$ ]]; then
  echo "FAIL: release CI requires an iOS 26 SDK; selected SDK is $ios_sdk." >&2
  exit 1
fi
echo "Stable Apple toolchain accepted: Xcode $xcode_version ($xcode_build), iOS SDK $ios_sdk."
