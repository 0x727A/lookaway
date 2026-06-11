import SwiftUI

struct SettingsView: View {
    private static let workFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 60
        formatter.allowsFloats = false
        return formatter
    }()

    private static let restFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 5
        formatter.maximum = 120
        formatter.allowsFloats = false
        return formatter
    }()

    @State var workMinutes: Int
    @State var restSeconds: Int
    @State var forceRest: Bool
    @State var playSoundOnRestEnd: Bool
    @State var playSoundOnRestStart: Bool
    @State var restStartSoundName: String
    @State var restEndSoundName: String
    @State var pauseVideo: Bool
    @State var launchAtLogin: Bool
    @State var displayMode: Int
    let onSave: (SettingsValues) -> Void
    let onCancel: () -> Void
    let onLaunchAtLoginChange: (Bool) -> Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("⚙️ 设置")
                .font(.system(size: 20, weight: .bold))

            // 工作时间
            VStack(alignment: .leading, spacing: 6) {
                Text("工作时间")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                HStack {
                    Slider(value: .init(
                        get: { Double(workMinutes) },
                        set: { workMinutes = min(max(Int($0), 1), 60) }
                    ), in: 1...60, step: 1)
                    .frame(width: 160)

                    TextField("", value: .init(
                        get: { workMinutes },
                        set: { workMinutes = min(max($0, 1), 60) }
                    ), formatter: Self.workFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)

                    Text("分钟")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            // 休息时间
            VStack(alignment: .leading, spacing: 6) {
                Text("休息时间")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                HStack {
                    Slider(value: .init(
                        get: { Double(restSeconds) },
                        set: { restSeconds = min(max(Int($0), 5), 120) }
                    ), in: 5...120, step: 5)
                    .frame(width: 160)

                    TextField("", value: .init(
                        get: { restSeconds },
                        set: { restSeconds = min(max($0, 5), 120) }
                    ), formatter: Self.restFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)

                    Text("秒")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            // 强制休息模式
            Toggle("强制休息模式（无法跳过）", isOn: $forceRest)
                .font(.system(size: 13))

            // 休息开始提示音
            HStack {
                Toggle("休息开始播放提示音", isOn: $playSoundOnRestStart)
                    .font(.system(size: 13))
                Picker("", selection: $restStartSoundName) {
                    ForEach(systemAlertSounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .labelsHidden()
            }

            // 休息结束提示音
            HStack {
                Toggle("休息结束播放提示音", isOn: $playSoundOnRestEnd)
                    .font(.system(size: 13))
                Picker("", selection: $restEndSoundName) {
                    ForEach(systemAlertSounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .labelsHidden()
            }

            // 休息开始时暂停视频
            Toggle("休息开始时暂停网页视频", isOn: $pauseVideo)
                .font(.system(size: 13))
                .help("需要在浏览器中开启“允许来自 Apple Events 的 JavaScript”。")

            // 登录时启动
            Toggle("登录时启动", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    let actualValue = onLaunchAtLoginChange(newValue)
                    launchAtLogin = actualValue
                }
            ))
            .font(.system(size: 13))

            // 显示模式
            VStack(alignment: .leading, spacing: 6) {
                Text("菜单栏显示")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Picker("", selection: $displayMode) {
                    Text("图标+时间").tag(0)
                    Text("仅时间").tag(1)
                    Text("极简图标").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    let clampedWork = min(max(workMinutes, 1), 60)
                    let clampedRest = min(max(restSeconds, 5), 120)
                    workMinutes = clampedWork
                    restSeconds = clampedRest
                    let safeStartSound = safeSound(restStartSoundName, fallback: "Ping")
                    let safeEndSound = safeSound(restEndSoundName, fallback: "Glass")
                    onSave(SettingsValues(
                        workMinutes: clampedWork,
                        restSeconds: clampedRest,
                        forceRest: forceRest,
                        playSoundOnRestEnd: playSoundOnRestEnd,
                        playSoundOnRestStart: playSoundOnRestStart,
                        restStartSoundName: safeStartSound,
                        restEndSoundName: safeEndSound,
                        pauseVideo: pauseVideo,
                        displayMode: displayMode
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)

            // 版本信息
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
            let commit = Bundle.main.infoDictionary?["LookAwayCommitHash"] as? String ?? "未知"
            Text("LookAway v\(version) (\(commit))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 320)
    }
}
