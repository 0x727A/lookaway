import Foundation

enum DefaultsKey {
    static let workDurationMinutes = "LookAway.workDurationMinutes"
    static let restDurationSeconds = "LookAway.restDurationSeconds"
    static let isForceRestMode = "LookAway.isForceRestMode"
    static let playSoundOnRestEnd = "LookAway.playSoundOnRestEnd"
    static let displayMode = "LookAway.displayMode"
    static let pauseVideoOnRestStart = "LookAway.pauseVideoOnRestStart"
    static let playSoundOnRestStart = "LookAway.playSoundOnRestStart"
    static let alertSoundName = "LookAway.alertSoundName"
    static let restStartSoundName = "LookAway.restStartSoundName"
    static let restEndSoundName = "LookAway.restEndSoundName"
}

let systemAlertSounds = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
    "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
    "Submarine", "Tink"
]

func safeSound(_ name: String?, fallback: String = "Glass") -> String {
    guard let name = name, systemAlertSounds.contains(name) else { return fallback }
    return name
}
