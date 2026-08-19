// One use of a skill as the systems that simulate it report it (issue #498,
// roadmap item 20.5), and the seam they report it through.
//
// The value carries what the emitting site knows — who acted, which kind of
// action it was, and the action's *base* experience in the vocabulary its own
// source states it in — and nothing about skills, thresholds or actor values.
// That split is the point: a combat runtime that had to know which actor value
// Light Armor lives at would be a combat runtime that has to change whenever
// progression does, and the skill an armoured hit credits is not even knowable
// from the hit (it depends on what the target is wearing).
//
// ## The base experience each action is worth
//
// UESP "Skyrim:Leveling" gives one line per skill, and its footnote defines the
// unit: "'Raw damage' refers to the damage before armor is taken into account."
//
// * One-Handed and Two-Handed: "Base Weapon Damage". The weapon's own WEAP
//   number, which is why perks, enchantments and tempering do not raise it —
//   "Boosting weapon damage via skill perks or equipment enchantments does not
//   result in more XP per strike, nor does improving your weapons at a
//   grindstone" (<https://en.uesp.net/wiki/Skyrim:One-handed>).
// * Archery: "Base Weapon Damage of the Bow".
// * Block: "1 base XP per raw damage blocked."
// * Heavy Armor and Light Armor: "1 base XP per raw damage received", scaled by
//   how much of that armour is worn (see `WornArmorProfile`).
// * The five magic schools: "Base Magicka Cost of the Spell", times the
//   effect's own `Skill Usage Mult` — "For Spells, a multiplier to the Skill
//   Uses (which feed into advancing the effect's Magic Skill, above) that
//   casting this effect will give the player"
//   (<https://ck.uesp.net/wiki/Magic_Effect>).
//
// Actions the engine does not simulate yet — lockpicking, pickpocketing,
// speech, the three crafting skills, sneaking — emit nothing at all rather than
// an event with a guessed amount. They are listed in
// docs/engine/skill-advancement.md as the wiring that is still open.
//
// Documented in docs/engine/skill-advancement.md.

import Foundation

/// What was done, in the emitting system's own terms.
///
/// A case per *action*, not per skill: the skill is a progression question, and
/// two of these cases cannot answer it on their own — a weapon hit's skill
/// depends on which animation family the weapon belongs to, and an armoured
/// hit's on what the target is wearing.
nonisolated enum SkillUseAction: Equatable, Sendable {
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

    /// The skill this action always credits, or nil when the action needs the
    /// target's equipment to answer — which is `armorHit` alone.
    ///
    /// Unarmed strikes credit nothing: "Unarmed combat does not have its own
    /// skill tree and cannot be developed like other skills"
    /// (<https://en.uesp.net/wiki/Skyrim:Unarmed_Combat>). Neither does a staff,
    /// a torch, a shield swing or a readied spell reported as a weapon hit,
    /// because none of those is a weapon strike the weapon skills claim.
    var skillIndex: Int32? {
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
        case let .spellEffect(skill):
            ActorValueIdentity.isSkill(index: skill) ? skill : nil
        }
    }
}

/// One skill use, from the system that simulated it.
nonisolated struct SkillUseEvent: Equatable, Sendable {
    /// Who used the skill. Only the player advances: "Advances the progress of
    /// the provided Skill by the given amount (for the player only)"
    /// (<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>), and NPCs in this engine
    /// stay on skills derived from their records.
    let actor: ReferenceKey
    let action: SkillUseAction
    /// The action's base experience, per the table quoted in this file's
    /// header. Zero or less is a use that is worth nothing and is dropped.
    let amount: Float
}

/// What one actor is wearing, as the armour skills count it.
///
/// Pieces rather than an armour rating, because the rating is explicitly not
/// what the experience scales on: "a character with an armor rating of 400 will
/// receive the same XP as a character with an armor rating of 100 for the same
/// enemy strike. The number of heavy armor items simultaneously worn by the
/// player does increase XP gained ... If the player is wearing a mixed set of
/// heavy and light armor, XP will only be awarded to one skill"
/// (<https://en.uesp.net/wiki/Skyrim:Heavy_Armor>).
///
/// Two readings of that paragraph are left open by it, and both are decided
/// here rather than left to a call site:
///
/// * *Which* skill a mixed set credits is not stated. The larger half takes it,
///   and heavy armour takes a tie — a reading, flagged as one, not a quotation.
/// * *How* the piece count raises the experience is not stated either, only
///   that it does. This scales it proportionally, which is the simplest
///   monotone reading and the one that makes a full four-piece set worth four
///   times a single bracer. The factor is unverified against the shipped game.
nonisolated struct WornArmorProfile: Equatable, Sendable {
    let heavyPieces: Int
    let lightPieces: Int

    static let none = WornArmorProfile(heavyPieces: 0, lightPieces: 0)

    init(heavyPieces: Int, lightPieces: Int) {
        self.heavyPieces = max(0, heavyPieces)
        self.lightPieces = max(0, lightPieces)
    }

    /// The armour skill a strike against this actor credits, and how many
    /// pieces of it are worn — or nil for an actor wearing no armour at all,
    /// whose strike credits nothing.
    var creditedSkill: (index: Int32, pieces: Int)? {
        guard heavyPieces > 0 || lightPieces > 0 else { return nil }
        let name = heavyPieces >= lightPieces ? "Heavy Armor" : "Light Armor"
        guard let index = ActorValueIdentity.index(named: name) else { return nil }
        return (index, max(heavyPieces, lightPieces))
    }
}

/// How a simulating system tells progression that a skill was used.
///
/// One method with a do-nothing default, exactly as `ScriptHitReporting`
/// carries one: `MeleeCombatWorld`, `ProjectileWorld`, `CombatLoopWorld` and
/// `CasterWorld` are the seams the acceptance tests drive against fakes with no
/// game data, and such a fake should not have to write an empty method to keep
/// compiling. Answering with the experience awarded rather than with nothing is
/// what lets a test assert that a blow reached progression at all.
@MainActor
protocol SkillUseReporting: AnyObject {
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
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        0
    }
}
