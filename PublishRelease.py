#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
import urllib.error

# 检查 GITHUB_TOKEN
token = os.environ.get("GITHUB_TOKEN")
if not token:
    print("错误: 请先设置 GITHUB_TOKEN 环境变量。")
    print("例如: export GITHUB_TOKEN=\"your_token_here\"")
    sys.exit(1)

owner = "0x727A"
repo = "lookaway"
tag = "v1.2.0"
title = "LookAway v1.2.0"
zip_path = "LookAway-1.2.0.zip"

body = """LookAway v1.2.0 是一次里程碑式的稳定性与体验更新，带来了多显示器插拔自适应、更多浏览器的进程隔离视频暂停、计时防误触作弊校验以及设置页交互优化。

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
解压附件中的 `LookAway-1.2.0.zip`，将其中的 `LookAway.app` 直接拖入 macOS 的「应用程序 (Applications)」文件夹即可运行。"""

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

print(f"正在创建 GitHub Release '{title}'...")
try:
    with urllib.request.urlopen(req) as response:
        res_data = json.loads(response.read().decode("utf-8"))
        release_id = res_data["id"]
        print(f"Release 创建成功! ID: {release_id}")
except urllib.error.HTTPError as e:
    err_body = e.read().decode("utf-8")
    if e.code == 422 and "already_exists" in err_body:
        print("-> 检测到该 v1.2.0 Release 已经在 GitHub 上存在。正在尝试获取其 ID 以进行覆盖更新...")
        existing = get_existing_release()
        if existing:
            release_id = existing["id"]
            print(f"-> 成功绑定到已有 Release! ID: {release_id}")
            
            # 检查是否有重名的老附件并清理
            assets = existing.get("assets", [])
            for asset in assets:
                if asset["name"] == zip_path:
                    print(f"-> 发现旧的同名附件 '{zip_path}'，正在进行删除释放...")
                    delete_asset(asset["id"])
        else:
            print("错误: 无法获取已存在的 Release 详情，终止流程。")
            sys.exit(1)
    else:
        print(f"创建失败，HTTP 错误 {e.code}: {err_body}")
        sys.exit(1)
except Exception as e:
    print(f"发生未知错误: {e}")
    sys.exit(1)

# 2. 上传最新的二进制文件
if not os.path.exists(zip_path):
    print(f"错误: 找不到要上传的发行文件 '{zip_path}'，请先确认文件存在。")
    sys.exit(1)

upload_url = f"https://uploads.github.com/repos/{owner}/{repo}/releases/{release_id}/assets?name={zip_path}"
headers_upload = headers.copy()
headers_upload["Content-Type"] = "application/zip"

print(f"正在上传最新构建的 {zip_path} 到 GitHub (可能需要一些网络时间)...")
try:
    with open(zip_path, "rb") as f:
        file_data = f.read()
    
    req_upload = urllib.request.Request(
        upload_url,
        data=file_data,
        headers=headers_upload,
        method="POST"
    )
    
    with urllib.request.urlopen(req_upload) as response:
        print("🎉 上传成功!")
        res_upload = json.loads(response.read().decode("utf-8"))
        print(f"⏬ 最终下载地址: {res_upload.get('browser_download_url')}")
        print("🚀 Release 发布及附件覆盖全部顺利完成!")
except urllib.error.HTTPError as e:
    print(f"上传附件失败，HTTP 错误 {e.code}: {e.read().decode('utf-8')}")
    sys.exit(1)
except Exception as e:
    print(f"上传过程中发生未知错误: {e}")
    sys.exit(1)
