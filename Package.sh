#!/bin/bash
set -e

echo "正在检查发布状态..."

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    echo "错误: 工作区存在未提交修改，拒绝打包。" >&2
    git status --short >&2
    exit 1
fi

if ! VERSION_TAG=$(git describe --tags --exact-match HEAD 2>/dev/null); then
    echo "错误: HEAD 没有精确对应版本 tag，拒绝打包。" >&2
    exit 1
fi

if [[ ! "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误: tag '$VERSION_TAG' 不符合 vX.Y.Z 格式。" >&2
    exit 1
fi

VERSION=${VERSION_TAG#v}
COMMIT_HASH=$(git rev-parse --short HEAD)

echo "正在构建 LookAway..."
swift build -c release

APP_BUNDLE="LookAway.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST="$CONTENTS_DIR/Info.plist"

echo "正在创建应用包结构..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "正在生成基础 Info.plist..."
cat > "$PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>LookAway</string>
    <key>CFBundleIdentifier</key>
    <string>com.lookaway.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LookAway</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "正在将二进制文件复制到 .app 包..."
cp .build/release/LookAway "$MACOS_DIR/LookAway"

echo "正在将图标复制到 .app 包..."
cp icon/LookAway.icns "$RESOURCES_DIR/"

echo "正在确保 Info.plist 中包含 NSAppleEventsUsageDescription..."
/usr/libexec/PlistBuddy -c "Set :NSAppleEventsUsageDescription 'LookAway 会在休息开始时向浏览器或视频播放器发送暂停命令，仅用于暂停正在播放的视频。'" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string 'LookAway 会在休息开始时向浏览器或视频播放器发送暂停命令，仅用于暂停正在播放的视频。'" "$PLIST"

echo "正在确保 Info.plist 中包含 CFBundleIconFile..."
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile 'LookAway'" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string 'LookAway'" "$PLIST"

echo "正在确保 Info.plist 中包含版本号 ${VERSION}..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString '$VERSION'" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string '$VERSION'" "$PLIST"

echo "正在写入当前 commit 哈希到 Info.plist..."
/usr/libexec/PlistBuddy -c "Set :LookAwayCommitHash '$COMMIT_HASH'" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :LookAwayCommitHash string '$COMMIT_HASH'" "$PLIST"

echo "正在使用 entitlements 签名（用于 Apple Events 自动化）..."
codesign --force --sign - --entitlements LookAway.entitlements LookAway.app

echo "构建完成: LookAway.app"
