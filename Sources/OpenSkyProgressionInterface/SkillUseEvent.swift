// One skill use as a simulating system reports it: who acted, the action kind and
// its base experience. The emitter knows nothing about skills, so combat need not
// change when progression does. Amounts follow UESP Skyrim:Leveling (raw damage,
// before armor, or base magicka cost times `Skill Usage Mult`). Unsimulated
// actions emit nothing. See docs/engine/skill-advancement.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM

/// What was done, in the emitting system's own terms.
///
/// A case per *action*, not per skill: the skill is a progression question, and
/// two of these cases cannot answer it on their own — a weapon hit's skill
/// depends on which animation family the weapon belongs to, and an armoured
/// hit's on what the target is wearing.
nonisolated public enum SkillUseAction: Equatable, Sendable {
    /// A landed strike, credited to the skill the weapon's animation family
    /// belongs to. The amount is the weapon's base damage.
    case weaponHit(CombatHandType)
    /// A blow the actor blocked. The amount is the raw damage the block
    /// absorbed.
    case blockedBlow
    /// A blow the actor took while wearing armour. The amount is the raw damage
    /// of the strike, before the worn-armour scaling this engine applies when
    /// it resolves which armour skill is credited.
    case armorHit
    /// Magicka spent on an effect, credited to the actor value that effect's
    /// MGEF names as its Magic Skill. The amount is already multiplied by the
    /// effect's `Skill Usage Mult`.
    case spellEffect(skill: Int32)
    /// An item made at a crafting station, credited to the station's `WBDT` skill.
    /// The amount is the made stack's base value.
    case craft(skill: Int32)
    /// A lock picked open or a pick broken, credited to Lockpicking. The amount is the
    /// `fSkillUsageLockPick*` setting for the event.
    case lockpick

    /// The skill this action always credits, or nil for `armorHit`, which depends
    /// on the target's armor. Unarmed, staff, torch and shield strikes credit
    /// nothing (<https://en.uesp.net/wiki/Skyrim:Unarmed_Combat>).
    public var skillIndex: Int32? {
        switch self {
        case let .weaponHit(handType):
            switch handType {
            case .sword, .dagger, .axe, .mace:
                ActorValueIdentity.index(named: "One-Handed")
            case .greatsword, .battleaxe:
                ActorValueIdentity.index(named: "Two-Handed")
            case .bow, .crossbow:
                ActorValueIdentity.index(named: "Archery")
            case .handToHand, .staff, .spell, .shield, .torch:
                nil
            }
        case .blockedBlow:
            ActorValueIdentity.index(named: "Block")
        case .armorHit:
            nil
        case .lockpick:
            ActorValueIdentity.index(named: "Lockpicking")
        case let .spellEffect(skill), let .craft(skill):
            ActorValueIdentity.isSkill(index: skill) ? skill : nil
        }
    }
}

/// One skill use, from the system that simulated it.
nonisolated public struct SkillUseEvent: Equatable, Sendable {
    /// Who used the skill. Only the player advances: "Advances the progress of
    /// the provided Skill by the given amount (for the player only)"
    /// (<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>), and NPCs in this engine
    /// stay on skills derived from their records.
    public let actor: ReferenceKey
    public let action: SkillUseAction
    /// The action's base experience, per the table quoted in this file's
    /// header. Zero or less is a use that is worth nothing and is dropped.
    public let amount: Float

    public init(actor: ReferenceKey, action: SkillUseAction, amount: Float) {
        self.actor = actor
        self.action = action
        self.amount = amount
    }
}

/// What one actor wears, as the armor skills count it: pieces, not rating
/// (<https://en.uesp.net/wiki/Skyrim:Heavy_Armor>). Our readings: a mixed set
/// credits the larger half (heavy wins a tie), and experience scales with the piece count.
nonisolated public struct WornArmorProfile: Equatable, Sendable {
    public let heavyPieces: Int
    public let lightPieces: Int

    public static let none = WornArmorProfile(heavyPieces: 0, lightPieces: 0)

    public init(heavyPieces: Int, lightPieces: Int) {
        self.heavyPieces = max(0, heavyPieces)
        self.lightPieces = max(0, lightPieces)
    }

    /// The armour skill a strike against this actor credits, and how many
    /// pieces of it are worn — or nil for an actor wearing no armour at all,
    /// whose strike credits nothing.
    public var creditedSkill: (index: Int32, pieces: Int)? {
        guard heavyPieces > 0 || lightPieces > 0 else { return nil }
        let name = heavyPieces >= lightPieces ? "Heavy Armor" : "Light Armor"
        guard let index = ActorValueIdentity.index(named: name) else { return nil }
        return (index, max(heavyPieces, lightPieces))
    }
}

/// How a simulating system reports a skill use. The default does nothing, so test
/// fakes need no empty method; the returned experience lets a test check delivery.
@MainActor
public protocol SkillUseReporting: AnyObject {
    /// Converts one use into skill experience on the acting character.
    ///
    /// - Returns: the skill experience awarded. Zero is the ordinary answer for
    ///   an NPC, for an action no skill claims, and for a session with no
    ///   progression runtime, and is never an error.
    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float
}

nonisolated extension SkillUseReporting {
    /// A world with no progression behind it awards nothing, which is what
    /// every acceptance fake wants and what a synthetic scene genuinely is.
    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        0
    }
}
