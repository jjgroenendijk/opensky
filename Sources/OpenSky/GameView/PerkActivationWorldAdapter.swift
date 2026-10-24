// App side of `PerkActivationCoordinator`: puts the player's Activate perk choices in
// front of the target's own action and answers `PerkActivationWorld` from the session
// systems. The rules live in `PerkActivationPlan` (docs/engine/perks.md).

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `PerkActivationWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol PerkActivationWorldHost: AnyObject {
    var magic: MagicCoordinator { get }
    var magicWorld: MagicWorldAdapter { get }
    var mapWorld: MapWorldAdapter { get }
    var perkActivation: PerkActivationCoordinator { get }
    var perks: PerkCoordinator { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
}

final class PerkActivationWorldAdapter {
    unowned let game: any PerkActivationWorldHost

    init(game: any PerkActivationWorldHost) {
        self.game = game
    }

    func wire(streamer: CellStreamer) {
        let coordinator = game.perkActivation
        streamer.activationGate.perkChoices = { [weak coordinator] target in
            coordinator?.activate(target) ?? false
        }
    }
}

extension PerkActivationWorldAdapter: PerkActivationWorld {
    func referenceKey(of target: InteractionTarget) -> ReferenceKey? {
        game.streamer?.referenceEntry(formID: target.interaction.reference)?.key
    }

    func activateChoices(on target: ReferenceKey) -> [PerkEntryPointChoice] {
        game.perks.choices(
            at: .activate,
            on: PerkActivationCoordinator.actor,
            subjects: { PerkEvaluationSubjects(owner: $0, target: target) },
            seams: ConditionContext()
        )
    }

    func text(_ value: LString) -> String? {
        game.mapWorld.text(value)
    }

    func runPerkFragment(
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

    func applyActivateSpell(
        _ spell: ResolvedSpell, caster: ReferenceKey, on target: ReferenceKey
    ) -> Bool {
        let report = game.magicWorld.applySpellHit(SpellHit(
            payload: spell.payload(caster: caster), targets: [SpellHitTarget(key: target)]
        ))
        return report.targetCount > 0
    }

    func performDefaultActivation(_ target: InteractionTarget) {
        game.streamer?.activate(target, offeringPerkChoices: false)
    }

    var crosshairTarget: InteractionTarget? {
        game.streamer?.interactionTarget
    }
}
