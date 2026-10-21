// A fake `MagicWorld` for the coordinator suite.
// Every answer is a stored value and every call is recorded.

import OpenSkyActorsInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface

@MainActor
final class FakeMagicWorld: MagicWorld {
    var gameDaysPassed: Float = 0
    var inventory: (any InventoryAccess)?
    var equipment: (any EquipmentAccess)?
    var residents: [ReferenceKey] = []
    var raceSpells: [FormID] = []
    var aim = SpellAim.none
    var canFireProjectile = true
    private(set) var firedProjectiles: [SpellPayload] = []
    private(set) var aimRequests: [(range: Float, caster: ReferenceKey)] = []
    private(set) var skillUses: [SkillUseEvent] = []
    private(set) var probedFunctions: [UInt16] = []
    var nearbyHostiles: [ReferenceKey] = []
    /// Every actor's perks at an entry point, as a factor on the value.
    var perkFactors: [PerkEntryPoint: Float] = [:]
    /// Every actor's perks at an entry point, as a value that replaces the input.
    var perkValues: [PerkEntryPoint: Float] = [:]
    private(set) var perkOwners: [PerkEntryPoint: ReferenceKey] = [:]
    /// Items with `ReusableSoulGem`.
    var reusableGems: Set<FormID> = []
    private(set) var bookRaises: [(skill: Int32, points: Int)] = []
    var undead: Set<ReferenceKey> = []
    /// Actors with `ActorTypeNPC`, whose souls are black.
    var npcs: Set<ReferenceKey> = []
    /// Resident actors beside the player.
    var holders: [ReferenceKey: ActorValueHolder] = [:]
    private(set) var notifications: [String] = []
    private(set) var cloakRadii: [Float] = []

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return 0
    }

    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        key == .player ? .player : holders[key]
    }

    func regeneratingHolders() -> [ActorValueHolder] {
        [.player]
    }

    func nearestActorValueHolder() -> ActorValueHolder? {
        nil
    }

    func residentActorKeys() -> [ReferenceKey] {
        residents
    }

    func actorName(_ holder: ActorValueHolder) -> String {
        holder.key.description
    }

    func itemName(_ item: FormID) -> String {
        "item \(item.rawValue)"
    }

    func playerRaceSpells() -> [FormID] {
        raceSpells
    }

    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        firedProjectiles.append(payload)
        return canFireProjectile
    }

    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        aimRequests.append((range, caster))
        return aim
    }

    func conditionText(
        of function: UInt16,
        parameter _: UInt32,
        in _: ConditionContext
    ) -> String {
        probedFunctions.append(function)
        return "probed"
    }

    func cloakTargets(around _: ReferenceKey, radius: Float) -> [ReferenceKey] {
        cloakRadii.append(radius)
        return nearbyHostiles
    }

    func actorHasKeyword(_ editorID: String, on holder: ActorValueHolder) -> Bool {
        editorID == "ActorTypeNPC" ? npcs.contains(holder.key) : undead.contains(holder.key)
    }

    func postNotification(_ text: String) {
        notifications.append(text)
    }

    var shoutKnowledge = ShoutKnowledge()
    var keywords: [String: ReferenceKey] = [:]
    /// Corpses `reanimate` may raise.
    var dead: Set<ReferenceKey> = []
    private(set) var summoned: [(base: FormID, caster: ReferenceKey)] = []
    private(set) var releasedActors: [CommandedActor] = []

    func summonActor(_ base: FormID, at _: SIMD3<Float>?, for caster: ReferenceKey)
        -> ReferenceKey?
    {
        summoned.append((base: base, caster: caster))
        return .generated(UInt64(summoned.count))
    }

    func reanimate(_ corpse: ReferenceKey, for _: ReferenceKey) -> Bool {
        dead.remove(corpse) != nil
    }

    func releaseCommandedActor(_ actor: CommandedActor) {
        releasedActors.append(actor)
    }

    func isActorDead(_ key: ReferenceKey) -> Bool {
        dead.contains(key)
    }

    var runeTargets: [MeleeTarget] = []

    func keyword(editorID: String) -> ReferenceKey? {
        keywords[editorID]
    }

    func runeTriggers(for _: ReferenceKey) -> [MeleeTarget] {
        runeTargets
    }

    func spellHitCandidates() -> [MeleeTarget] {
        runeTargets
    }

    func changeShoutKnowledge(_ change: ShoutKnowledgeChange) {
        switch change {
        case let .addShout(shout): shoutKnowledge.shouts.insert(shout)
        case let .equip(shout): shoutKnowledge.equipped = shout
        case let .teachWord(word): shoutKnowledge.knownWords.insert(word)
        case let .unlockWord(word): shoutKnowledge.unlockedWords.insert(word)
        }
    }

    func itemHasKeyword(_ editorID: String, on item: FormID) -> Bool {
        editorID == "ReusableSoulGem" && reusableGems.contains(item)
    }

    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects _: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> Float {
        perkOwners[entryPoint] = key
        return perkValues[entryPoint] ?? value * (perkFactors[entryPoint] ?? 1)
    }

    func raiseSkillFromBook(_ skill: Int32, points: Int) -> Int {
        bookRaises.append((skill: skill, points: points))
        return points
    }
}
