# Task List

- [ ] Split `Sources/my_lookaway/main.swift` into focused Swift files without changing behavior.
  - Target files: `LookAwayApp.swift`, `Constants.swift`, `RestSession.swift`, `VideoPauser.swift`, `AppDelegate.swift`, `SettingsView.swift`, `RestView.swift`.
  - Keep the refactor mechanical: no renamed APIs, no UI copy changes, no timer/lock/video behavior changes.
  - After splitting, run the package script and verify settings, rest windows, lock handling, and video pause behavior.

- [ ] Replace deprecated activation calls and document the settings-window focus workaround.
  - Current code uses `NSRunningApplication.activate(options:)` to make a menu-bar accessory app's settings window interactive on first click.
  - Investigate `NSApp.activate()` and `NSRunningApplication.activate(from:options:)` without regressing the previously fixed first-click issue.
  - Keep or replace the double activation only after verifying settings opens from the menu and the first click inside the window works.
