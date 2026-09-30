// World > Combat & Physics destination panel. Sections follow a fight: actor
// values, melee, archery, death, hostility, and physics.

import AppKit
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyMagic
import OpenSkyPhysics

final class CombatPhysicsPanelViewController: InspectorPanelViewController {
    let actorValuesSection = CombatActorValuesSection()
    let magicEffectsSection = CombatMagicEffectsSection()
    let spellcastingSection = CombatSpellcastingSection()
    let meleeSection = CombatMeleeSection()
    let archerySection = CombatArcherySection()
    let ragdollSection = CombatRagdollSection()
    let loopSection = CombatLoopSection()
    let physicsSection = CombatPhysicsSection()

    /// Actor values. Weak throughout, for the reason every other panel holds
    /// its providers weakly: the game controller owns this panel's parent and
    /// the renderer, so the panel must not retain back.
    weak var actorValueProvider: (any ActorValueControlProviding)? {
        didSet { actorValuesSection.provider = actorValueProvider }
    }

    weak var magicEffectProvider: (any MagicEffectControlProviding)? {
        didSet { magicEffectsSection.provider = magicEffectProvider }
    }

    weak var castingProvider: (any CastingControlProviding)? {
        didSet { spellcastingSection.provider = castingProvider }
    }

    weak var meleeProvider: (any MeleeCombatControlProviding)? {
        didSet { meleeSection.provider = meleeProvider }
    }

    weak var archeryProvider: (any ArcheryControlProviding)? {
        didSet { archerySection.provider = archeryProvider }
    }

    weak var ragdollProvider: (any RagdollControlProviding)? {
        didSet { ragdollSection.provider = ragdollProvider }
    }

    weak var combatProvider: (any CombatLoopControlProviding)? {
        didSet { loopSection.provider = combatProvider }
    }

    weak var physicsProvider: (any PhysicsControlProviding)? {
        didSet { physicsSection.provider = physicsProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [
            actorValuesSection, magicEffectsSection, spellcastingSection, meleeSection,
            archerySection, ragdollSection, loopSection, physicsSection
        ]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// PlayerLocomotionPanelViewController's convention.
    var damageControl: NSButton {
        actorValuesSection.damageControl
    }

    var spellcastingLearnControl: NSButton {
        spellcastingSection.learnControl
    }

    var spellcastingCastRightControl: NSButton {
        spellcastingSection.castRightControl
    }

    var weaponDrawnControl: NSButton {
        meleeSection.weaponDrawnControl
    }

    var attackControl: NSButton {
        meleeSection.attackControl
    }

    var archerySpawnControl: NSButton {
        archerySection.spawnControl
    }

    var ragdollTriggerControl: NSButton {
        ragdollSection.triggerControl
    }

    var hostilityControl: NSButton {
        loopSection.hostilityControl
    }

    /// The 19.10 switch: whether fighters cast the spells they know.
    var actorCastingControl: NSButton {
        loopSection.castingControl
    }

    var clearCombatTraceControl: NSButton {
        loopSection.clearTraceControl
    }

    var physicsFreezeControl: NSButton {
        physicsSection.freezeControl
    }

    var physicsResetControl: NSButton {
        physicsSection.resetControl
    }
}
