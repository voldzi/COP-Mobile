#!/usr/bin/env bash
set -euo pipefail

required_xcode_version="${COP_REQUIRED_XCODE_VERSION:-27.0}"
required_xcode_build="${COP_REQUIRED_XCODE_BUILD:-27A5228h}"
required_ios_sdk="${COP_REQUIRED_IOS_SDK:-27.0}"

xcode_version="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
xcode_build="$(xcodebuild -version | sed -n '2s/^Build version //p')"
ios_sdk="$(xcrun --sdk iphoneos --show-sdk-version)"

if [[ "$xcode_version" != "$required_xcode_version" || "$xcode_build" != "$required_xcode_build" ]]; then
  echo "FAIL: approved toolchain is Xcode $required_xcode_version ($required_xcode_build); selected Xcode is $xcode_version ($xcode_build)." >&2
  exit 1
fi
if [[ "$ios_sdk" != "$required_ios_sdk" ]]; then
  echo "FAIL: approved iOS SDK is $required_ios_sdk; selected SDK is $ios_sdk." >&2
  exit 1
fi
echo "Approved Apple toolchain accepted: Xcode $xcode_version ($xcode_build), iOS SDK $ios_sdk."
