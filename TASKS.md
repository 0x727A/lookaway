# 任务清单

- [ ] 将 `Sources/my_lookaway/main.swift` 拆分为多个职责单一的 Swift 文件，保持行为不变。
  - 目标文件：`LookAwayApp.swift`、`Constants.swift`、`RestSession.swift`、`VideoPauser.swift`、`AppDelegate.swift`、`SettingsView.swift`、`RestView.swift`。
  - 保持纯机械拆分：不修改 API 名称、不改动 UI 文案、不改动计时器/锁屏/视频暂停行为。
  - 拆分后运行打包脚本，验证设置窗口、休息窗口、锁屏处理、视频暂停功能均正常。

- [ ] 替换已弃用的窗口激活调用，并记录设置窗口焦点问题的解决方案。
  - 当前代码使用 `NSRunningApplication.activate(options:)` 让菜单栏附属应用的设置窗口在首次点击时获得交互焦点。
  - 调研 `NSApp.activate()` 和 `NSRunningApplication.activate(from:options:)`，确保不破坏此前修复的首次点击问题。
  - 仅在验证设置窗口可从菜单打开且窗口内首次点击有效后，保留或替换双重激活逻辑。
