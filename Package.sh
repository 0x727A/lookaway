#!/bin/bash
set -e

echo "正在构建 LookAway..."
swift build -c release

echo "正在将二进制文件复制到 .app 包..."
cp .build/release/LookAway LookAway.app/Contents/MacOS/LookAway

echo "正在将图标复制到 .app 包..."
mkdir -p LookAway.app/Contents/Resources
cp icon/LookAway.icns LookAway.app/Contents/Resources/

echo "正在确保 Info.plist 中包含 NSAppleEventsUsageDescription..."
PLIST="LookAway.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSAppleEventsUsageDescription 'LookAway 会在休息开始时向浏览器或视频播放器发送暂停命令，仅用于暂停正在播放的视频。'" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string 'LookAway 会在休息开始时向浏览器或视频播放器发送暂停命令，仅用于暂停正在播放的视频。'" "$PLIST"

echo "正在确保 Info.plist 中包含 CFBundleIconFile..."
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile 'LookAway'" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string 'LookAway'" "$PLIST"

echo "正在写入当前 commit 哈希到 Info.plist..."
COMMIT_HASH=$(git rev-parse --short HEAD)
/usr/libexec/PlistBuddy -c "Set :LookAwayCommitHash '$COMMIT_HASH'" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :LookAwayCommitHash string '$COMMIT_HASH'" "$PLIST"

echo "正在使用 entitlements 签名（用于 Apple Events 自动化）..."
codesign --force --sign - --entitlements LookAway.entitlements LookAway.app

echo "构建完成: LookAway.app"
