import Foundation

enum DisplayMode: Int {
    case iconAndTime = 0
    case timeOnly = 1
    case minimalIcon = 2
}

struct SettingsValues {
    let workMinutes: Int
    let restSeconds: Int
    let forceRest: Bool
    let playSoundOnRestEnd: Bool
    let playSoundOnRestStart: Bool
    let restStartSoundName: String
    let restEndSoundName: String
    let pauseVideo: Bool
    let displayMode: DisplayMode
}
