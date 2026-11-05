// The game's sound category mix: each SNCT's static volume down its parent chain, and the
// default-object categories that fade or pause in menus, duck under dialogue, or mute under
// water. Pure; the engine applies it. See docs/engine/sound-mix.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

/// The `DOBJ` tags that name a sound category with a rule.
nonisolated public enum SoundCategoryRole: String, CaseIterable, Sendable {
    case pausedDuringMenuFade = "PDMC"
    case pausedDuringMenuImmediate = "PIMC"
    case pausedDuringLoading = "PDLC"
    case fadesInDialogue = "SFDC"
    case dialogueVoice = "DDSC"
    case nonDialogueVoice = "NDSC"
    case music = "MDSC"
    case statsMute = "SMSC"

    /// Each role's category, merged by tag over every plugin's `DOBJ`; the last wins.
    public static func roles(
        in loadOrder: LoadOrderPlugins, skipped: inout SkippedRecords
    ) -> [SoundCategoryRole: FormID] {
        let versions = loadOrder.decodeEveryVersion(of: "DOBJ", skipped: &skipped) {
            try DefaultObjects(record: $0)
        }
        var result: [SoundCategoryRole: FormID] = [:]
        for key in versions.keys.sorted() {
            for version in versions[key] ?? [] {
                for role in allCases {
                    guard let entry = version.entry(tag: role.rawValue) else { continue }
                    result[role] = entry.object
                }
            }
        }
        return result
    }
}

/// The `[Audio]` INI seconds of the menu fade and the music duck.
nonisolated public struct SoundMixTimings: Equatable, Sendable {
    public var musicDuckSeconds: Float = 6
    public var musicUnduckSeconds: Float = 8
    public var menuFadeOutSeconds: Float = 3
    public var menuFadeInSeconds: Float = 1

    public init() {}

    public init(ini: INISettings) {
        func read(_ key: String, _ fallback: Float) -> Float {
            ini.float(section: "Audio", key: key)?.value ?? fallback
        }
        musicDuckSeconds = read("fMusicDuckingSeconds", musicDuckSeconds)
        musicUnduckSeconds = read("fMusicUnDuckingSeconds", musicUnduckSeconds)
        menuFadeOutSeconds = read("fMenuModeFadeOutTime", menuFadeOutSeconds)
        menuFadeInSeconds = read("fMenuModeFadeInTime", menuFadeInSeconds)
    }
}

/// What the mix follows each frame.
nonisolated public struct SoundMixInputs: Equatable, Sendable {
    public var menuMode = false
    public var loading = false
    public var dialogue = false
    public var submerged = false
    public var statsMenu = false

    public init(
        menuMode: Bool = false, loading: Bool = false, dialogue: Bool = false,
        submerged: Bool = false, statsMenu: Bool = false
    ) {
        self.menuMode = menuMode
        self.loading = loading
        self.dialogue = dialogue
        self.submerged = submerged
        self.statsMenu = statsMenu
    }
}

/// One category's share of the mix now, and whether its sounds hold still.
nonisolated public struct SoundCategoryLevel: Equatable, Sendable {
    public var gain: Float
    public var paused: Bool
}

nonisolated public struct SoundCategoryMix: Sendable {
    /// Music's level under dialogue; OpenSky's value.
    public static let musicDuckLevel: Float = 0.4
    /// The level of the dialogue-fade sounds and of other voices under dialogue; OpenSky's.
    public static let dialogueDuckLevel: Float = 0.5

    public let categories: [UInt32: SoundCategory]
    public let roles: [SoundCategoryRole: FormID]
    public var timings: SoundMixTimings
    public private(set) var inputs = SoundMixInputs()
    /// 1 out of menus; falls to 0 over the menu fade-out time.
    public private(set) var menuLevel: Float = 1
    public private(set) var dialogueLevel: Float = 1
    public private(set) var musicLevel: Float = 1

    public init(
        categories: [UInt32: SoundCategory], roles: [SoundCategoryRole: FormID],
        timings: SoundMixTimings = SoundMixTimings()
    ) {
        self.categories = categories
        self.roles = roles
        self.timings = timings
    }

    public mutating func advance(_ inputs: SoundMixInputs, seconds: Float) {
        self.inputs = inputs
        let step = max(seconds.isFinite ? seconds : 0, 0)
        menuLevel = Self.ramp(
            menuLevel, to: inputs.menuMode ? 0 : 1, seconds: step,
            down: timings.menuFadeOutSeconds, up: timings.menuFadeInSeconds
        )
        dialogueLevel = Self.ramp(
            dialogueLevel, to: inputs.dialogue ? Self.dialogueDuckLevel : 1, seconds: step,
            down: timings.musicDuckSeconds, up: timings.musicUnduckSeconds
        )
        musicLevel = Self.ramp(
            musicLevel, to: inputs.dialogue ? Self.musicDuckLevel : 1, seconds: step,
            down: timings.musicDuckSeconds, up: timings.musicUnduckSeconds
        )
    }

    /// The category with `editorID`, for a sound that names none.
    public func category(editorID: String) -> FormID? {
        categories.values.first { $0.editorID?.caseInsensitiveCompare(editorID) == .orderedSame }?
            .formID
    }

    /// The level of a sound in `category`, walking its parents to the master category.
    public func level(of category: FormID?) -> SoundCategoryLevel {
        var gain: Float = 1
        var paused = false
        var current = category
        var visited: Set<FormID> = []
        while let id = current, visited.insert(id).inserted, let node = categories[id.rawValue] {
            gain *= node.staticVolumeMultiplier ?? 1
            if node.flags.contains(.muteWhenSubmerged), inputs.submerged {
                gain = 0
            }
            for role in roles.filter({ $0.value == id }).map(\.key) {
                apply(role, gain: &gain, paused: &paused)
            }
            current = node.parent
        }
        return SoundCategoryLevel(gain: max(gain, 0), paused: paused)
    }

    private func apply(_ role: SoundCategoryRole, gain: inout Float, paused: inout Bool) {
        switch role {
        case .pausedDuringMenuFade:
            gain *= menuLevel
            paused = paused || (inputs.menuMode && menuLevel <= 0)
        case .pausedDuringMenuImmediate:
            paused = paused || inputs.menuMode
        case .pausedDuringLoading:
            paused = paused || inputs.loading
        case .fadesInDialogue, .nonDialogueVoice:
            gain *= dialogueLevel
        case .music:
            gain *= musicLevel
        case .statsMute:
            if inputs.statsMenu {
                gain = 0
            }
        case .dialogueVoice:
            break
        }
    }

    /// Moves `value` toward `target` at a rate that crosses the full range in `down`
    /// seconds when falling and `up` seconds when rising.
    static func ramp(
        _ value: Float,
        to target: Float,
        seconds: Float,
        down: Float,
        up: Float
    ) -> Float {
        let span = target < value ? down : up
        guard span > 0 else { return target }
        let step = seconds / span
        return target < value ? max(target, value - step) : min(target, value + step)
    }
}
