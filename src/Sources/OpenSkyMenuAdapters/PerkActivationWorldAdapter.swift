// App side of `PerkActivationCoordinator`: puts the player's Activate perk choices in
// front of the target's own action and answers `PerkActivationWorld` from the session
// systems. The rules live in `PerkActivationPlan` (docs/engine/perks.md).

import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyMagicInterface
public import OpenSkyMenus
public import OpenSkyProgressionInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `PerkActivationWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol PerkActivationWorldHost: AnyObject, SendableMetatype {
    var magicWorld: any MagicWorldPort { get }
    var mapWorld: any MapWorldPort { get }
    var perkActivation: any PerkActivationPort { get }
    var perks: any PerkPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
}

public final class PerkActivationWorldAdapter {
    public let game: any PerkActivationWorldHost

    public init(game: any PerkActivationWorldHost) {
        self.game = game
    }
}

extension PerkActivationWorldAdapter: PerkActivationWorld {
    public func referenceKey(of target: InteractionTarget) -> ReferenceKey? {
        game.streamer.referenceEntry(formID: target.interaction.reference)?.key
    }

    public func activateChoices(on target: ReferenceKey) -> [PerkEntryPointChoice] {
        game.perks.choices(
            at: .activate,
            on: PerkActivationCoordinator.actor,
            subjects: { PerkEvaluationSubjects(owner: $0, target: target) },
            seams: ConditionContext()
        )
    }

    public func text(_ value: LString) -> String? {
        game.mapWorld.text(value)
    }

    public var activationChoiceMessage: String {
        game.mapWorld.settingTexts(ActivationChoiceText.self)[.message]
    }

    public func runPerkFragment(
        _ choice: PerkActivateChoice, actor: ReferenceKey, target: ReferenceKey
    ) -> Bool {
        guard
            let perk = choice.perk,
            let key = choice.perkKey,
            let index = choice.fragmentIndex,
            let bridge = game.scripts.bridge
        else { return false }
        return bridge.runPerkFragment(
            of: perk.record, key: key, index: index,
            activation: PerkFragmentActivation(actor: actor, target: target)
        )
    }

    public func applyActivateSpell(
        _ spell: ResolvedSpell, caster: ReferenceKey, on target: ReferenceKey
    ) -> Bool {
        let report = game.magicWorld.applySpellHit(SpellHit(
            payload: spell.payload(caster: caster), targets: [SpellHitTarget(key: target)]
        ))
        return report.targetCount > 0
    }

    public func performDefaultActivation(_ target: InteractionTarget) {
        game.streamer.activate(target, offeringPerkChoices: false)
    }

    public var crosshairTarget: InteractionTarget? {
        game.streamer.interactionTarget
    }
}
