// The facts of one combat detection dialogue pass, and the lines it asks for.
// See docs/engine/combat-detection-dialogue.md.

public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import simd

/// One NPC in a fight, as the detection dialogue sees it.
nonisolated public struct DetectionMember: Equatable, Sendable {
    public let key: ReferenceKey
    /// Whom it fights. Members with one target form a group.
    public let target: ReferenceKey
    public let feet: SIMD3<Float>
    /// It searches for a target it lost; false while it fights a target it detects.
    public let isSearching: Bool
    /// Alive, in no scene or conversation, and within hearing range of the camera.
    public let canSpeak: Bool

    public init(
        key: ReferenceKey, target: ReferenceKey, feet: SIMD3<Float>, isSearching: Bool,
        canSpeak: Bool = true
    ) {
        self.key = key
        self.target = target
        self.feet = feet
        self.isSearching = isSearching
        self.canSpeak = canSpeak
    }
}

nonisolated public struct DetectionDialogueFrame: Equatable, Sendable {
    public var members: [DetectionMember]
    /// Seconds on the clock the speech waits use.
    public var now: Double
    /// Where each target stands, or was last known to stand.
    public var targetPositions: [ReferenceKey: SIMD3<Float>]
    public var deadTargets: Set<ReferenceKey>
    public var playerFeet: SIMD3<Float>

    public init(
        members: [DetectionMember], now: Double,
        targetPositions: [ReferenceKey: SIMD3<Float>] = [:],
        deadTargets: Set<ReferenceKey> = [], playerFeet: SIMD3<Float> = .zero
    ) {
        self.members = members
        self.now = now
        self.targetPositions = targetPositions
        self.deadTargets = deadTargets
        self.playerFeet = playerFeet
    }
}

/// A group's record of one target.
nonisolated public enum DetectionRecord: String, Equatable, Sendable {
    case normal
    case alert
    case combat
    case lost
}

/// The detection subtypes of `DIAL` records, by their four-letter codes.
nonisolated public enum DetectionSubtype: String, Equatable, Sendable, CaseIterable {
    case alertIdle
    case lostIdle
    case normalToAlert
    case alertToCombat
    case normalToCombat
    case alertToNormal
    case combatToNormal
    case combatToLost
    case lostToNormal
    case lostToCombat

    public var code: FourCC {
        switch self {
        case .alertIdle: "ALIL"
        case .lostIdle: "LOIL"
        case .normalToAlert: "NOTA"
        case .alertToCombat: "ALTC"
        case .normalToCombat: "NOTC"
        case .alertToNormal: "ALTN"
        case .combatToNormal: "COTN"
        case .combatToLost: "COLO"
        case .lostToNormal: "LOTN"
        case .lostToCombat: "LOTC"
        }
    }

    /// The two idle lines wait longer than the lines of a change.
    public var isIdle: Bool {
        self == .alertIdle || self == .lostIdle
    }
}

/// A line a member wants to say about its group's target.
nonisolated public struct DetectionLineRequest: Equatable, Sendable {
    public let subtype: DetectionSubtype
    public let speaker: ReferenceKey
    public let about: ReferenceKey

    public init(subtype: DetectionSubtype, speaker: ReferenceKey, about: ReferenceKey) {
        self.subtype = subtype
        self.speaker = speaker
        self.about = about
    }
}

/// A detection line that was found and recorded as said.
nonisolated public struct DetectionLine: Equatable, Sendable {
    public let info: FormID
    public let request: DetectionLineRequest

    public init(info: FormID, request: DetectionLineRequest) {
        self.info = info
        self.request = request
    }
}
