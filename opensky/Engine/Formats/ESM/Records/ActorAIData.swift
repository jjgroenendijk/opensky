// NPC_ AIDT: the AI attributes that decide when an actor starts a fight, how
// long it stays in one, and who it helps (issue #503, roadmap item 21.3).
//
// The faction and relationship records say how two actors *regard* each other.
// They do not say whether that regard turns into a drawn weapon: the Creation
// Kit puts that on the actor, in the Aggression value, "in conjunction with
// Faction Relationships, determines when the Actor will initiate combat"
// (<https://ck.uesp.net/wiki/AI_Data_Tab>). So the hostility derivation reads
// this struct beside the reaction, and `ActorReactionResolver` is where the two
// meet.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/NPC_", AIDT: 20-byte struct, uint8
//   Aggression, uint8 Confidence, uint8 Energy, uint8 Morality, uint8 Mood,
//   uint8 Assistance, uint8 flags, uint8 unknown, uint32 Warn, uint32
//   Warn/Attack, uint32 Attack.
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbAIDT`, which reads the same
//   eight bytes and names offset 7 "Unused".
//   Value names per <https://ck.uesp.net/wiki/AI_Data_Tab>.
// Layout documented in docs/formats/actors.md.

import Foundation

/// AIDT offset 0. When the actor draws on somebody it is not already fighting.
///
/// The descriptions are the Creation Kit's own, and the derivation quotes them
/// rather than paraphrasing: "Aggressive: will attack Enemies on sight. Very
/// Aggressive: will attack Enemies and Neutrals on sight. Frenzied: will attack
/// anyone on sight."
nonisolated enum ActorAggression: Equatable, Sendable, CustomStringConvertible {
    case unaggressive
    case aggressive
    case veryAggressive
    case frenzied
    /// A value outside 0...3. Kept rather than clamped, the rule every other
    /// enum decoded from external data here follows: a mod may author one, and
    /// clamping would silently turn it into a real setting.
    case unknown(raw: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .unaggressive
        case 1: self = .aggressive
        case 2: self = .veryAggressive
        case 3: self = .frenzied
        default: self = .unknown(raw: rawValue)
        }
    }

    var rawValue: UInt8 {
        switch self {
        case .unaggressive: 0
        case .aggressive: 1
        case .veryAggressive: 2
        case .frenzied: 3
        case let .unknown(raw): raw
        }
    }

    var description: String {
        switch self {
        case .unaggressive: "unaggressive"
        case .aggressive: "aggressive"
        case .veryAggressive: "very aggressive"
        case .frenzied: "frenzied"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// AIDT offset 1. When the actor avoids or flees a threat.
///
/// Decoded but not consumed by the hostility derivation: the Creation Kit's
/// "Cowardly actors NEVER engage in combat" is about *engaging*, not about
/// regard, and this engine's two-case `ActorHostility` records regard alone.
/// Whoever wires fleeing reads it from here rather than re-decoding the byte.
nonisolated enum ActorConfidence: Equatable, Sendable, CustomStringConvertible {
    case cowardly
    case cautious
    case average
    case brave
    case foolhardy
    case unknown(raw: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .cowardly
        case 1: self = .cautious
        case 2: self = .average
        case 3: self = .brave
        case 4: self = .foolhardy
        default: self = .unknown(raw: rawValue)
        }
    }

    var rawValue: UInt8 {
        switch self {
        case .cowardly: 0
        case .cautious: 1
        case .average: 2
        case .brave: 3
        case .foolhardy: 4
        case let .unknown(raw): raw
        }
    }

    var description: String {
        switch self {
        case .cowardly: "cowardly"
        case .cautious: "cautious"
        case .average: "average"
        case .brave: "brave"
        case .foolhardy: "foolhardy"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// AIDT offset 5. Whom the actor joins a fight for.
nonisolated enum ActorAssistance: Equatable, Sendable, CustomStringConvertible {
    case helpsNobody
    case helpsAllies
    case helpsFriendsAndAllies
    case unknown(raw: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .helpsNobody
        case 1: self = .helpsAllies
        case 2: self = .helpsFriendsAndAllies
        default: self = .unknown(raw: rawValue)
        }
    }

    var rawValue: UInt8 {
        switch self {
        case .helpsNobody: 0
        case .helpsAllies: 1
        case .helpsFriendsAndAllies: 2
        case let .unknown(raw): raw
        }
    }

    var description: String {
        switch self {
        case .helpsNobody: "helps nobody"
        case .helpsAllies: "helps allies"
        case .helpsFriendsAndAllies: "helps friends and allies"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// AIDT offset 3. Which crimes the actor will commit on the player's orders.
/// Decoded for completeness and for the crime work of issues #504 and #505.
nonisolated enum ActorMorality: Equatable, Sendable, CustomStringConvertible {
    case anyCrime
    case violenceAgainstEnemies
    case propertyCrimeOnly
    case noCrime
    case unknown(raw: UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .anyCrime
        case 1: self = .violenceAgainstEnemies
        case 2: self = .propertyCrimeOnly
        case 3: self = .noCrime
        default: self = .unknown(raw: rawValue)
        }
    }

    var rawValue: UInt8 {
        switch self {
        case .anyCrime: 0
        case .violenceAgainstEnemies: 1
        case .propertyCrimeOnly: 2
        case .noCrime: 3
        case let .unknown(raw): raw
        }
    }

    var description: String {
        switch self {
        case .anyCrime: "any crime"
        case .violenceAgainstEnemies: "violence against enemies"
        case .propertyCrimeOnly: "property crime only"
        case .noCrime: "no crime"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// The whole AIDT struct, 20 bytes.
///
/// Decoded from the payload length rather than a record version, the rule the
/// FACT structs beside it follow: a plugin that writes a shorter AIDT keeps the
/// bytes it did author and loses only the aggro radii, instead of failing the
/// record. Every field past offset 7 is optional for that reason.
nonisolated struct ActorAIData: Equatable, Sendable {
    /// Offsets 0...5 plus the two flag bytes. A record shorter than this has no
    /// readable AI data at all.
    static let requiredByteCount = 8
    static let byteCount = 20

    let aggression: ActorAggression
    let confidence: ActorConfidence
    /// Offset 2. How often a sandboxing actor moves, 0...100. Not an AI
    /// attribute the derivation reads.
    let energy: UInt8
    let morality: ActorMorality
    /// Offset 4. The Creation Kit wiki calls Mood "Not used", so it is kept
    /// verbatim and never interpreted.
    let mood: UInt8
    let assistance: ActorAssistance
    /// Offset 6 bit 0, which the Creation Kit calls "Aggro Radius Behavior" and
    /// which is what enables the three distances below.
    let usesAggroRadiusBehavior: Bool
    /// Offset 7. xEdit names it "Unused" and UESP observes junk in it, so it is
    /// kept verbatim rather than read as anything.
    let unknown: UInt8
    let warnDistance: UInt32?
    let warnOrAttackDistance: UInt32?
    let attackDistance: UInt32?

    /// The value an actor whose record authors no AIDT reads as.
    ///
    /// Unaggressive rather than aggressive: a record with no AI data has said
    /// nothing about starting fights, and inventing a willingness to attack out
    /// of an absent field is exactly the guess this engine refuses to make.
    static let absent = ActorAIData(
        aggression: .unaggressive,
        confidence: .average,
        energy: 0,
        morality: .anyCrime,
        mood: 0,
        assistance: .helpsNobody,
        usesAggroRadiusBehavior: false,
        unknown: 0,
        warnDistance: nil,
        warnOrAttackDistance: nil,
        attackDistance: nil
    )

    init(
        aggression: ActorAggression,
        confidence: ActorConfidence,
        energy: UInt8,
        morality: ActorMorality,
        mood: UInt8,
        assistance: ActorAssistance,
        usesAggroRadiusBehavior: Bool,
        unknown: UInt8,
        warnDistance: UInt32?,
        warnOrAttackDistance: UInt32?,
        attackDistance: UInt32?
    ) {
        self.aggression = aggression
        self.confidence = confidence
        self.energy = energy
        self.morality = morality
        self.mood = mood
        self.assistance = assistance
        self.usesAggroRadiusBehavior = usesAggroRadiusBehavior
        self.unknown = unknown
        self.warnDistance = warnDistance
        self.warnOrAttackDistance = warnOrAttackDistance
        self.attackDistance = attackDistance
    }

    init(field: ESMField) throws {
        guard field.data.count >= Self.requiredByteCount else {
            throw ESMError.malformed(
                "NPC_ AIDT has \(field.data.count) bytes,"
                    + " expected at least \(Self.requiredByteCount)"
            )
        }
        var reader = BinaryReader(field.data)
        aggression = try ActorAggression(rawValue: reader.readUInt8())
        confidence = try ActorConfidence(rawValue: reader.readUInt8())
        energy = try reader.readUInt8()
        morality = try ActorMorality(rawValue: reader.readUInt8())
        mood = try reader.readUInt8()
        assistance = try ActorAssistance(rawValue: reader.readUInt8())
        usesAggroRadiusBehavior = try reader.readUInt8() & 0x01 != 0
        unknown = try reader.readUInt8()
        warnDistance = try? reader.readUInt32()
        warnOrAttackDistance = try? reader.readUInt32()
        attackDistance = try? reader.readUInt32()
    }
}
