#!/usr/bin/env python3
import os
import sys
import json
import re
import subprocess
import uuid
import urllib.request
import urllib.error

status_result = subprocess.run(
    ["git", "status", "--porcelain", "--untracked-files=all"],
    capture_output=True,
    text=True,
)
if status_result.returncode != 0:
    print(f"错误: 无法检查工作区状态: {status_result.stderr.strip()}")
    sys.exit(1)

if status_result.stdout:
    print("错误: 工作区存在未提交修改，拒绝发布。")
    print(status_result.stdout, end="")
    sys.exit(1)

tag_result = subprocess.run(
    ["git", "describe", "--tags", "--exact-match", "HEAD"],
    capture_output=True,
    text=True,
)
if tag_result.returncode != 0:
    print("错误: HEAD 没有精确对应版本 tag，拒绝发布。")
    sys.exit(1)

tag = tag_result.stdout.strip()
if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
    print(f"错误: tag '{tag}' 不符合 vX.Y.Z 格式。")
    sys.exit(1)

version = tag.removeprefix("v")
title = f"LookAway {tag}"
zip_path = f"LookAway-{version}.zip"

# 检查 GITHUB_TOKEN
token = os.environ.get("GITHUB_TOKEN")
if not token:
    print("错误: 请先设置 GITHUB_TOKEN 环境变量。")
    print("例如: export GITHUB_TOKEN=\"your_token_here\"")
    sys.exit(1)

owner = "0x727A"
repo = "lookaway"

body = f"""LookAway {tag} 是一次里程碑式的稳定性与体验更新，带来了多显示器插拔自适应、更多浏览器的进程隔离视频暂停、计时防误触作弊校验以及设置页交互优化。

## 🚀 新增与改进
- **多浏览器支持 (Edge/Arc/Brave)**：视频暂停组件新增了对 Microsoft Edge、Arc 和 Brave 浏览器的完美适配。
- **进程隔离与异步执行**：弃用了有主线程阻塞风险的 `NSAppleScript` 机制，重构为利用 `Process` 后台异步执行 `/usr/bin/osascript`，彻底解决了 Strict Concurrency 下的线程安全隐患。
- **多显示器热插拔适配**：新增对系统屏幕配置和分辨率变化的监听，能在休息遮挡激活期间自适应调整、重新生成所有屏幕的全屏遮挡窗口，防止绕过。
- **防误触/作弊重置机制**：引入 system 睡眠/锁屏开始时间校验，当挂起时长少于设定的休息时间时，重新进入系统后将恢复原有的倒计时，而不会错误重置为满额。
- **提示音即时预览**：在设置页中更改开始/结束提示音时，增加即时播放试听，提供更好的用户反馈。
- **自动化构建优化**：打包脚本 `Package.sh` 升级为自动提取并过滤 Git Tag 中的前导字符，确保 macOS `CFBundleShortVersionString` 规范。

## 🧹 架构与可维护性
- **类型安全重构**：将 displayMode 参数从 `Int` 重构为强类型 `DisplayMode` 枚举，从编译期消除类型隐患。
- **全局命名空间化**：封装全局提示音与辅助函数到 `SoundUtils` 中，清空模块级全局命名空间污染。
- **提交记录规范化**：重写了整个 Git 本地与远程提交历史，将全仓库提交日志规范化为中文。

## 📦 使用说明
解压附件中的 `{zip_path}`，将其中的 `LookAway.app` 直接拖入 macOS 的「应用程序 (Applications)」文件夹即可运行。"""

headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "LookAway-Release-Script"
}

def get_existing_release():
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}"
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as e:
        print(f"获取已有的 Release 页面失败: {e}")
        return None

def delete_asset(asset_id):
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}"
    req = urllib.request.Request(url, headers=headers, method="DELETE")
    try:
        with urllib.request.urlopen(req) as response:
            print(f"-> 成功清理已有的同名发布附件 (Asset ID: {asset_id})。")
            return True
    except Exception as e:
        print(f"-> 清理旧分发附件失败: {e}")
        return False

def upload_asset(release_id, name, file_data):
    url = f"https://uploads.github.com/repos/{owner}/{repo}/releases/{release_id}/assets?name={name}"
    headers_upload = headers.copy()
    headers_upload["Content-Type"] = "application/zip"
    req_upload = urllib.request.Request(
        url,
        data=file_data,
        headers=headers_upload,
        method="POST"
    )

    try:
        with urllib.request.urlopen(req_upload) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"上传附件失败，HTTP 错误 {e.code}: {e.read().decode('utf-8')}")
        return None
    except Exception as e:
        print(f"上传过程中发生未知错误: {e}")
        return None

def rename_asset(asset_id, new_name):
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}"
    headers_update = headers.copy()
    headers_update["Content-Type"] = "application/json"
    req_rename = urllib.request.Request(
        url,
        data=json.dumps({"name": new_name}).encode("utf-8"),
        headers=headers_update,
        method="PATCH"
    )

    try:
        with urllib.request.urlopen(req_rename) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"重命名附件失败，HTTP 错误 {e.code}: {e.read().decode('utf-8')}")
        return None
    except Exception as e:
        print(f"重命名附件时发生未知错误: {e}")
        return None

def is_valid_asset(asset, expected_name, expected_size):
    return (
        isinstance(asset, dict)
        and isinstance(asset.get("id"), int)
        and asset["id"] > 0
        and asset.get("name") == expected_name
        and asset.get("state") == "uploaded"
        and asset.get("size") == expected_size
    )

if not os.path.exists(zip_path):
    print(f"错误: 找不到要上传的发行文件 '{zip_path}'，请先确认文件存在。")
    sys.exit(1)

with open(zip_path, "rb") as f:
    file_data = f.read()

# 1. 创建 Release
create_url = f"https://api.github.com/repos/{owner}/{repo}/releases"
data = {
    "tag_name": tag,
    "target_commitish": "main",
    "name": title,
    "body": body,
    "draft": False,
    "prerelease": False
}

req = urllib.request.Request(
    create_url,
    data=json.dumps(data).encode("utf-8"),
    headers=headers,
    method="POST"
)

release_id = None
old_asset = None

print(f"正在创建 GitHub Release '{title}'...")
try:
    with urllib.request.urlopen(req) as response:
        res_data = json.loads(response.read().decode("utf-8"))
        release_id = res_data["id"]
        print(f"Release 创建成功! ID: {release_id}")
except urllib.error.HTTPError as e:
    err_body = e.read().decode("utf-8")
    if e.code == 422 and "already_exists" in err_body:
        print(f"-> 检测到该 {tag} Release 已经在 GitHub 上存在。正在尝试获取其 ID 以进行覆盖更新...")
        existing = get_existing_release()
        if existing:
            release_id = existing["id"]
            print(f"-> 成功绑定到已有 Release! ID: {release_id}")
            
            # 记录同名旧附件，待临时附件验证成功后再删除。
            assets = existing.get("assets", [])
            old_asset = next(
                (asset for asset in assets if asset["name"] == zip_path),
                None,
            )
            if old_asset:
                print(f"-> 发现旧的同名附件 '{zip_path}'，将在新附件验证后替换。")
        else:
            print("错误: 无法获取已存在的 Release 详情，终止流程。")
            sys.exit(1)
    else:
        print(f"创建失败，HTTP 错误 {e.code}: {err_body}")
        sys.exit(1)
except Exception as e:
    print(f"发生未知错误: {e}")
    sys.exit(1)

# 2. 临时上传、验证并替换附件
temp_name = f"LookAway-{version}-upload-{uuid.uuid4().hex}.zip"
print(f"正在上传临时附件 {temp_name} 到 GitHub (可能需要一些网络时间)...")
temp_asset = upload_asset(release_id, temp_name, file_data)

if not is_valid_asset(temp_asset, temp_name, len(file_data)):
    print("错误: 临时附件上传响应未通过验证，旧附件保持不动。")
    temp_asset_id = temp_asset.get("id") if isinstance(temp_asset, dict) else None
    if isinstance(temp_asset_id, int) and temp_asset_id > 0:
        cleanup_succeeded = delete_asset(temp_asset_id)
        if not cleanup_succeeded:
            print(f"警告: 无法清理临时附件 (Asset ID: {temp_asset_id})。")
    sys.exit(1)

temp_asset_id = temp_asset["id"]
if old_asset:
    old_asset_id = old_asset.get("id")
    if not isinstance(old_asset_id, int) or old_asset_id <= 0:
        print("错误: 旧附件缺少有效 ID，停止重命名临时附件。")
        cleanup_succeeded = delete_asset(temp_asset_id)
        if not cleanup_succeeded:
            print(f"警告: 无法清理临时附件 (Asset ID: {temp_asset_id})。")
        sys.exit(1)

    if not delete_asset(old_asset_id):
        print("错误: 删除旧附件失败，停止重命名临时附件。")
        cleanup_succeeded = delete_asset(temp_asset_id)
        if not cleanup_succeeded:
            print(f"警告: 无法清理临时附件 (Asset ID: {temp_asset_id})。")
        sys.exit(1)

renamed_asset = rename_asset(temp_asset_id, zip_path)
if not is_valid_asset(renamed_asset, zip_path, len(file_data)):
    print("错误: 临时附件重命名或验证失败，临时附件未被删除。")
    print(f"临时附件 ID: {temp_asset_id}")
    print(f"临时附件名称: {temp_name}")
    print(f"临时附件下载地址: {temp_asset.get('browser_download_url')}")
    sys.exit(1)

print("🎉 上传成功!")
print(f"⏬ 最终下载地址: {renamed_asset.get('browser_download_url')}")
print("🚀 Release 发布及附件覆盖全部顺利完成!")
