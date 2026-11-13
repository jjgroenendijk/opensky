import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPlayer
public import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MagicWorldFactsAdapter` reads from the session.
@MainActor
public protocol MagicWorldFactsHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var messages: any MessageCoordinatorPort { get }
    var perks: any PerkPort { get }
    var progression: any ProgressionPort { get }
}

/// Part of `MagicWorldAdapter`, over its own narrow host.
public struct MagicWorldFactsAdapter {
    public let game: any MagicWorldFactsHost
}

extension MagicWorldFactsAdapter {
    var gameDaysPassed: Float {
        game.gameSession?.gameClock.daysPassed ?? 0
    }

    var inventory: (any InventoryAccess)? {
        game.inventory.runtime?.inventory
    }

    var equipment: (any EquipmentAccess)? {
        game.inventory.equipment
    }

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.progression.reportSkillUse(game.combat.adjustingForDifficulty(use))
    }

    public func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        game.actorWorld.actorValueHolder(for: key)
    }

    public func regeneratingHolders() -> [ActorValueHolder] {
        game.actorWorld.regeneratingHolders()
    }

    public func nearestActorValueHolder() -> ActorValueHolder? {
        game.actorWorld.nearestActorValueHolder()
    }

    public func residentActorKeys() -> [ReferenceKey] {
        game.actorWorld.combatActors().map(\.key)
    }

    public func actorName(_ holder: ActorValueHolder) -> String {
        holder.readoutName
    }

    public func displayName(of holder: ActorValueHolder) -> String? {
        guard case let .actor(base) = holder.subject else { return nil }
        return game.actorWorld.displayName(of: holder.key, base: base)
    }

    public func itemName(_ item: FormID) -> String {
        game.inventory.name(of: item)
    }

    public func conditionText(
        of function: UInt16,
        parameter: UInt32,
        in context: ConditionContext
    ) -> String {
        var context = context
        context.functions = .standard
        return ConditionProbe.text(of: function, parameter1: parameter, in: context)
    }

    public func playerAteIngredient(_ item: FormID) {
        let lab = game.inventory.alchemyLab
        for notice in lab.eatingNotices(of: lab.learnEatenIngredient(item)) {
            _ = game.messages.postNotification(notice)
        }
    }

    public func postNotification(_ text: String) {
        _ = game.messages.postNotification(text)
    }

    public func announceSpellLearned(_ name: String) {
        game.messages.postWorldNotice(.spellLearned(name: name))
    }

    public func raiseSkillFromBook(_ skill: Int32, points: Int) -> Int {
        (0 ..< max(0, points)).reduce(0) { raised, _ in
            raised + (game.progression.incrementSkill(skill) ? 1 : 0)
        }
    }

    public func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        given conditions: (subjects: PerkEvaluationSubjects, seams: ConditionContext)
    ) -> Float {
        game.perks.modified(
            value,
            at: entryPoint,
            on: key,
            subjects: { _ in conditions.subjects },
            seams: conditions.seams
        )
    }
}
