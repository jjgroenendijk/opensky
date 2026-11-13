import OpenSkyAIPackages
import OpenSkyCells
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
public import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `InventoryPerksAdapter` reads from the session.
@MainActor
public protocol InventoryPerksHost: AnyObject, SendableMetatype {
    var inventory: any InventoryPort { get }
    var mapWorld: any MapWorldPort { get }
    var perkActivation: any PerkActivationPort { get }
    var perks: any PerkPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `InventoryWorldAdapter`, over its own narrow host.
public struct InventoryPerksAdapter {
    public let game: any InventoryPerksHost
}

extension InventoryPerksAdapter {
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

    public func magicEffectName(_ effect: ResolvedMagicEffect) -> String {
        game.mapWorld.text(effect.effect.name) ?? effect.displayName
    }

    public func perkActivateLabel(for reference: FormID) -> String? {
        guard let key = game.streamer.referenceEntry(formID: reference)?.key else { return nil }
        if let label = game.perkActivation.promptLabel(on: key) {
            return label
        }
        let choice = game.perks.choices(
            at: .setActivateLabel,
            on: .player,
            subjects: { _ in PerkEvaluationSubjects(owner: .player, target: key) },
            seams: ConditionContext()
        ).first
        if case let .localizedText(text)? = choice?.text {
            return game.mapWorld.text(text)
        }
        return choice?.inlineText
    }

    /// The streamer's target with the runtime label, such as a harvested plant's.
    public func labelled(_ target: InteractionTarget?) -> InteractionTarget? {
        target.map {
            InteractionTarget(
                interaction: game.inventory.craftingBench.labelled($0.interaction),
                hitPosition: $0.hitPosition,
                distance: $0.distance
            )
        }
    }
}
