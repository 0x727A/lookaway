#!/bin/bash
set -e

echo "Building LookAway..."
swift build -c release

echo "Copying binary into .app bundle..."
cp .build/release/LookAway LookAway.app/Contents/MacOS/LookAway

echo "Copying icon into .app bundle..."
mkdir -p LookAway.app/Contents/Resources
cp icon/LookAway.icns LookAway.app/Contents/Resources/

echo "Ensuring NSAppleEventsUsageDescription in Info.plist..."
PLIST="LookAway.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSAppleEventsUsageDescription 'LookAway 会在休息开始时向浏览器或视频播放器发送暂停命令，仅用于暂停正在播放的视频。'" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string 'LookAway 会在休息开始时向浏览器或视频播放器发送暂停命令，仅用于暂停正在播放的视频。'" "$PLIST"

echo "Build complete: LookAway.app"
echo ""
echo "NOTE: To sign with entitlements (for Apple Events automation):"
echo "  codesign --force --sign - --entitlements LookAway.entitlements LookAway.app"
