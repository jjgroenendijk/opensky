// World > Combat & Physics destination panel (issue #198, roadmap item 15.9):
// the sidebar verification surface for the whole M15 fight, composed from
// sections items 15.2 through 15.7 each specified a provider seam for.
//
// A destination of its own rather than more sections under `World > Player &
// Locomotion`, which is where Melee, Archery and Death & Ragdoll landed while
// they were three controls each. Six sections and six readouts is past the
// promotion threshold in docs/tools/app-ui.md, and the M15 gate names this path
// top-level, which outranks the threshold anyway.
//
// Section order follows the order a fight happens in: what the actors are worth,
// what the player swings, what the player shoots, what dies, who is angry, and
// what the physics is carrying while all of it runs.

import AppKit

final class CombatPhysicsPanelViewController: InspectorPanelViewController {
    let actorValuesSection = CombatActorValuesSection()
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
            actorValuesSection, meleeSection, archerySection,
            ragdollSection, loopSection, physicsSection
        ]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// PlayerLocomotionPanelViewController's convention.
    var damageControl: NSButton {
        actorValuesSection.damageControl
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
