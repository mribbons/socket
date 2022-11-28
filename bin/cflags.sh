#!/usr/bin/env bash

declare root="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"

declare IPHONEOS_VERSION_MIN="${IPHONEOS_VERSION_MIN:-11.0}"
declare IOS_SIMULATOR_VERSION_MIN="${IOS_SIMULATOR_VERSION_MIN:-$IPHONEOS_VERSION_MIN}"

declare cflags=("-stdlib=libc++")
declare arch="$(uname -m)"
declare platform="desktop"

declare ios_sdk_path=""

if (( TARGET_OS_IPHONE )) || (( TARGET_IPHONE_SIMULATOR )); then
  if (( TARGET_OS_IPHONE )); then
    ios_sdk_path="$(xcrun -sdk iphoneos -show-sdk-path)"
    cflags+=("-arch arm64")
    cflags+=("-target arm64-apple-ios")
    cflags+=("-miphoneos-version-min=$IPHONEOS_VERSION_MIN")
  elif (( TARGET_IPHONE_SIMULATOR )); then
    ios_sdk_path="$(xcrun -sdk iphonesimulator -show-sdk-path)"
    cflags+=("-arch x86_64")
    cflags+=("-mios-simulator-version-min=$IPHONEOS_VERSION_MIN")
  fi

  cflags+=("-iframeworkwithsysroot /System/Library/Frameworks")
  cflags+=("-isysroot $ios_sdk_path/")
  cflags+=("-F $ios_sdk_path/System/Library/Frameworks/")
  cflags+=("-fembed-bitcode")

  test -d "$ios_sdk_path/lib/system" && cflags+=("-L $ios_sdk_path/lib/system")
  test -d "$ios_sdk_path/usr/lib" && cflags+=("-L $ios_sdk_path/usr/lib")
fi

cflags+=(
  $CFLAG
  $CXXFLAGS
  -std=c++20
  -I"$root/include"
  -I"$root/build/uv/include"
  -DSSC_BUILD_TIME="$(date '+%s')"
  -DSSC_VERSION_HASH=`git rev-parse --short HEAD`
  -DSSC_VERSION=`cat "$root/VERSION.txt"`
  -Wno-unused-command-line-argument
)

if [[ "$(uname -s)" = "Darwin" ]]; then
  cflags+=("-ObjC++")
elif [[ "$(uname -s)" = "Linux" ]]; then
  cflags+=($(pkg-config --cflags --static gtk+-3.0 webkit2gtk-4.1))
fi

while (( $# > 0 )); do
  cflags+=("$1")
  shift
done

echo "${cflags[@]}"
