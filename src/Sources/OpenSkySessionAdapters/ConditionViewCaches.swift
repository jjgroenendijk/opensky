// The condition views the live context keeps across frames, each with the inputs
// it was built from. See docs/engine/runtime-state.md#caching-derived-views.

import OpenSkyActorsInterface
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyWorldState

@MainActor
public final class ConditionViewCaches {
    let deaths = RevisionCache<DeathViewKey, DeathView>()
    let markers = RevisionCache<MarkerViewKey, Set<ReferenceKey>>()
    public let inventory = RevisionCache<InventoryViewKey, InventoryConditionResolution>()
    let actors = RevisionCache<ActorViewKey, [ReferenceKey: ActorConditionState]>()
}

/// A death is an `ActorDeathState` write. A spawned actor's base is known only while
/// its cell is resident, so the resident cells are part of the key.
struct DeathViewKey: Hashable {
    let store: ObjectIdentifier
    let streamer: ObjectIdentifier?
    let cells: Set<CellSceneLocation>?
    let deaths: UInt64
}

public struct DeathView {
    public var dead: Set<ReferenceKey> = []
    public var counts: [FormID: Int] = [:]
}

struct MarkerViewKey: Hashable {
    let store: ObjectIdentifier
    let markers: UInt64
    let references: [ReferenceKey]
}

/// Item stacks and equip flags are inventory writes; an actor's baseline equipment is
/// fixed by its record. The hand type also reads which hands hold a spell.
public struct InventoryViewKey: Hashable {
    public let runtime: ObjectIdentifier
    public let writes: UInt64
    public let actors: [ReferenceKey]
    public let spellHands: [Set<SpellHand>]
    public let hasEquipment: Bool
}

/// The NPC states only: the player's also reads its gait, melee graph and race menu,
/// so it is built fresh every frame.
struct ActorViewKey: Hashable {
    let store: ObjectIdentifier
    let writes: UInt64
    let playerLevel: Int
    let hasInventory: Bool
    let actors: [ActorViewMember]
    /// Nil without a combat loop, where an NPC reports no action at all.
    let phases: [ReferenceKey: CombatBehaviorPhase]?
}

struct ActorViewMember: Hashable {
    let holder: ActorValueHolder
    let isDead: Bool
}
