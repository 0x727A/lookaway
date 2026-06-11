# 任务清单

- [x] 将 `Sources/my_lookaway/main.swift` 拆分为多个职责单一的 Swift 文件，保持行为不变。
  - 最终结构：
    - `LookAwayApp.swift` — @main 入口
    - `AppDelegate.swift` — 主类、属性、生命周期、quit()
    - `AppDelegate+MenuBar.swift` — 菜单栏显示/绘制
    - `AppDelegate+WorkTimer.swift` — 工作计时器、tick、暂停切换
    - `AppDelegate+SystemActivity.swift` — 系统睡眠/屏幕/会话/锁屏
    - `AppDelegate+LaunchAtLogin.swift` — 登录时启动
    - `AppDelegate+SettingsWindow.swift` — 设置窗口
    - `AppDelegate+RestWindow.swift` — 休息窗口、提示音
    - `Support/Defaults.swift` — DefaultsKey、systemAlertSounds、safeSound
    - `Models/SettingsValues.swift` — DisplayMode、SettingsValues
    - `Services/RestSession.swift` — RestSession
    - `Services/VideoPauser.swift` — VideoPauser
    - `Views/SettingsView.swift` — SettingsView
    - `Views/RestView.swift` — RestView
  - 纯机械拆分：未修改 API 名称、未改动 UI 文案、未改动计时器/锁屏/视频暂停行为。
  - 拆分后 `swift build` 通过，`git diff --check` 无警告。

- [ ] 替换已弃用的窗口激活调用，并记录设置窗口焦点问题的解决方案。
  - 当前代码使用 `NSRunningApplication.activate(options:)` 让菜单栏附属应用的设置窗口在首次点击时获得交互焦点。
  - 调研 `NSApp.activate()` 和 `NSRunningApplication.activate(from:options:)`，确保不破坏此前修复的首次点击问题。
  - 仅在验证设置窗口可从菜单打开且窗口内首次点击有效后，保留或替换双重激活逻辑。
