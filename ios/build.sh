#!/usr/bin/env bash
#
# Generates the SatDump iOS Xcode project with CMake.
#
# After running this, open build-ios/SatDump.xcodeproj in Xcode, select the
# SatDump scheme and a device/simulator, set your signing team and build.
#
# Prerequisites:
#   - macOS with Xcode and the iOS SDK
#   - CMake 3.20 or newer
#   - Prebuilt iOS dependencies under ios/deps (see ios/deps/README.md)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build-ios"
DEPLOYMENT_TARGET="14.0"

cmake -S "${ROOT_DIR}" -B "${BUILD_DIR}" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO

echo ""
echo "Xcode project generated: ${BUILD_DIR}/SatDump.xcodeproj"
echo "Open it in Xcode, set your signing team and build the SatDump scheme."
