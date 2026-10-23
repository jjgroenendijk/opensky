// The condition views the live context keeps across frames, each with the inputs
// it was built from. See docs/engine/runtime-state.md#caching-derived-views.

import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldState

@MainActor
final class ConditionViewCaches {
    let deaths = RevisionCache<DeathViewKey, DeathView>()
    let markers = RevisionCache<MarkerViewKey, Set<ReferenceKey>>()
    let inventory = RevisionCache<InventoryViewKey, InventoryConditionResolution>()
    let actors = RevisionCache<ActorViewKey, [ReferenceKey: ActorConditionState]>()
}

/// A death is an `ActorDeathState` write. A spawned actor's base is known only while
/// its cell is resident, so the resident cells are part of the key.
struct DeathViewKey: Equatable {
    let store: ObjectIdentifier
    let streamer: ObjectIdentifier?
    let cells: Set<CellSceneLocation>?
    let deaths: UInt64
}

struct DeathView {
    var dead: Set<ReferenceKey> = []
    var counts: [FormID: Int] = [:]
}

struct MarkerViewKey: Equatable {
    let store: ObjectIdentifier
    let markers: UInt64
    let references: [ReferenceKey]
}

/// Item stacks and equip flags are inventory writes; an actor's baseline equipment is
/// fixed by its record. The hand type also reads which hands hold a spell.
struct InventoryViewKey: Equatable {
    let runtime: ObjectIdentifier
    let writes: UInt64
    let actors: [ReferenceKey]
    let spellHands: [Set<SpellHand>]
    let hasEquipment: Bool
}

/// The NPC states only: the player's also reads its gait, melee graph and race menu,
/// so it is built fresh every frame.
struct ActorViewKey: Equatable {
    let store: ObjectIdentifier
    let writes: UInt64
    let playerLevel: Int
    let hasInventory: Bool
    let actors: [ActorViewMember]
    /// Nil without a combat loop, where an NPC reports no action at all.
    let phases: [ReferenceKey: CombatBehaviorPhase]?
}

struct ActorViewMember: Equatable {
    let holder: ActorValueHolder
    let isDead: Bool
}
