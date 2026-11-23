// The alarm a seen crime raises: who hears it, the hostility test, and the Alarm
// package's decide step. Values in, values out; `CrimeCoordinator+Alarm` reads the
// world and carries out the result. See docs/engine/crime-reports.md#the-alarm.

public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// One crime an alarm carries.
nonisolated public struct AlarmCrime: Equatable, Sendable {
    public let id: Int
    public let kind: CrimeKind
    public let criminal: ReferenceKey
    /// The crime's faction. The first guard to take it may move it to its own.
    public internal(set) var faction: ReferenceKey
    /// The pickpocket target, the assault victim, or a theft's owner.
    public let victim: ReferenceKey?
    public let gold: Int32
    public let violent: Bool
    public let stolenItem: FormID?
    public let stolenCount: Int32
    /// The guard that took the crime. Then no other guard hears it.
    public internal(set) var takenBy: ReferenceKey?
}

/// What a witness does after the decide step.
nonisolated public enum AlarmRole: String, Equatable, Sendable {
    case pursue, fight, done, flee, takeBack
}

/// One actor that runs an Alarm package.
nonisolated public struct AlarmWitness: Equatable, Sendable {
    public internal(set) var crimes: [Int]
    public internal(set) var role: AlarmRole
    /// Seconds in the current role.
    var elapsed: Double = 0
    /// Seconds since the last Pursue line.
    var sinceLine: Double = 0
    var lastTarget: SIMD3<Float>?
    /// After a take back ran out of time, the next decide skips it.
    var gaveUpTakingBack = false

    init(crimes: [Int], role: AlarmRole) {
        self.crimes = crimes
        self.role = role
    }
}

/// What the alarm reads about one possible hearer.
nonisolated struct AlarmHearer: Equatable, Sendable {
    let distance: Float
    /// The faction a guard polices; nil for anyone else.
    let policedFaction: ReferenceKey?
    let crimeFaction: ReferenceKey?
    /// The factions in the `CRGR` list of the hearer's crime faction.
    let sharedCrimeFactions: Set<ReferenceKey>
    let isHostile: Bool
}

/// One crime in a witness's package, as the decide step reads it.
nonisolated struct AlarmCrimeView: Equatable, Sendable {
    let isTaken: Bool
    let mayTakeBack: Bool
    let fights: Bool
}

/// The player's recent theft mark. It keeps the game day it was set; the next
/// theft on another day only clears it.
nonisolated public struct TheftMark: Equatable, Sendable {
    public private(set) var day: Int?

    public var isSet: Bool {
        day != nil
    }

    public init(day: Int? = nil) {
        self.day = day
    }

    mutating func note(day today: Int) {
        if let day, day != today {
            self.day = nil
        } else {
            day = today
        }
    }
}

nonisolated enum CrimeAlarmRules {
    /// How far from the criminal an actor hears the alarm.
    static let reach: Float = 4000
    /// At most this many guards answer one criminal.
    static let guardCap = 4
    /// A take back that has not reached the player by then decides again.
    static let takeBackSeconds: Double = 20
    /// A pursuing guard says its Pursue line this often.
    static let pursueLineSeconds: Double = 3

    static func hears(_ hearer: AlarmHearer, _ crime: AlarmCrime) -> Bool {
        guard hearer.distance <= reach else { return false }
        if hearer.policedFaction != nil {
            return crime.takenBy == nil
        }
        guard
            let own = hearer.crimeFaction,
            own == crime.faction || hearer.sharedCrimeFactions.contains(crime.faction)
        else { return false }
        return hearer.isHostile
    }

    /// A theft, a pickpocket, or a trespass. Anything worse makes only its victim fight.
    static func isLesser(_ kind: CrimeKind) -> Bool {
        kind == .theft || kind == .pickpocket || kind == .trespass
    }

    /// The witness's reaction to the criminal from its relationship rank, then its factions.
    static func reaction(relationship: ActorReaction?, faction: ActorReaction?) -> ActorReaction {
        let start = relationship ?? .neutral
        guard start != .ally, let faction else { return start }
        return switch start {
        case .neutral: faction
        case .enemy: faction == .neutral ? .enemy : faction
        case .friend: faction == .ally ? .ally : .friend
        case .ally: .ally
        }
    }

    /// Whether the witness is hostile to the criminal. `criminalTargetsWitness`: an NPC
    /// criminal fights this witness and does not flee.
    static func isHostile(
        aggression: ActorAggression,
        reaction: ActorReaction,
        isAngry: Bool,
        criminalTargetsWitness: Bool
    ) -> Bool {
        if case .frenzied = aggression {
            return true
        }
        if criminalTargetsWitness {
            return reaction != .ally && reaction != .friend
        }
        if isAngry {
            return true
        }
        return switch aggression {
        case .aggressive: reaction == .enemy
        case .veryAggressive: reaction == .enemy || reaction == .neutral
        // Aggression 0 also needs the player marked to be attacked on sight, which
        // OpenSky does not keep.
        case .unaggressive, .frenzied, .unknown: false
        }
    }

    /// The role, and whether the witness becomes angry with the player.
    static func decide(
        isGuard: Bool, crimes: [AlarmCrimeView], theftMark: Bool
    ) -> (role: AlarmRole, angry: Bool) {
        if isGuard {
            return (.pursue, false)
        }
        if crimes.contains(where: \.fights) {
            return (.fight, false)
        }
        if crimes.contains(where: \.isTaken) {
            return (.done, false)
        }
        guard crimes.contains(where: \.mayTakeBack) else { return (.flee, false) }
        return theftMark ? (.fight, true) : (.takeBack, false)
    }

    /// Where an NPC criminal runs to when a guard answers and it is not fighting.
    static func fleePoint(
        criminal: SIMD3<Float>, from pursuer: SIMD3<Float>, distance: Float
    ) -> SIMD3<Float> {
        var away = criminal - pursuer
        away.z = 0
        let length = simd_length(away)
        let direction = length > 0.001 ? away / length : SIMD3<Float>(1, 0, 0)
        return criminal + direction * distance
    }
}

/// The session's alarms: the crimes they carry, who runs an Alarm package, and who
/// fights whom because of one. Session state, as `pendingReports` is.
nonisolated public struct CrimeAlarmState: Equatable, Sendable {
    public internal(set) var crimes: [Int: AlarmCrime] = [:]
    public internal(set) var witnesses: [ReferenceKey: AlarmWitness] = [:]
    /// Per witness, the criminals it fights.
    public internal(set) var fighters: [ReferenceKey: Set<ReferenceKey>] = [:]
    /// Per criminal, the guards that answered.
    public internal(set) var answering: [ReferenceKey: Set<ReferenceKey>] = [:]
    /// Witnesses angry with the player: their hostility tests pass.
    public internal(set) var angry: Set<ReferenceKey> = []
    public internal(set) var theftMark = TheftMark()
    private var nextID = 0

    public init() {}

    mutating func add(
        _ event: CrimeEvent, faction: ReferenceKey, gold: Int32
    ) -> Int {
        let id = nextID
        nextID += 1
        crimes[id] = AlarmCrime(
            id: id, kind: event.kind, criminal: event.perpetrator, faction: faction,
            victim: event.victim, gold: gold, violent: event.kind.isViolent,
            stolenItem: event.stolenItem, stolenCount: event.stolenCount
        )
        return id
    }

    /// The criminal a witness's package aims at.
    func criminal(of witness: AlarmWitness) -> ReferenceKey? {
        witness.crimes.first.flatMap { crimes[$0]?.criminal }
    }

    mutating func fight(_ witness: ReferenceKey, against criminal: ReferenceKey) {
        fighters[witness, default: []].insert(criminal)
    }
}
