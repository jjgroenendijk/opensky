// The condition views the live context keeps across frames, each with the inputs
// it was built from. See docs/engine/runtime-state.md#caching-derived-views.

public import OpenSkyActorsInterface
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyWorldState

@MainActor
public final class ConditionViewCaches {
    public let deaths = RevisionCache<DeathViewKey, DeathView>()
    public let markers = RevisionCache<MarkerViewKey, Set<ReferenceKey>>()
    public let inventory = RevisionCache<InventoryViewKey, InventoryConditionResolution>()
    public let actors = RevisionCache<ActorViewKey, [ReferenceKey: ActorConditionState]>()
}

/// A death is an `ActorDeathState` write. A spawned actor's base is known only while
/// its cell is resident, so the resident cells are part of the key.
public struct DeathViewKey: Hashable {
    public let store: ObjectIdentifier
    public let streamer: ObjectIdentifier?
    public let cells: Set<CellSceneLocation>?
    public let deaths: UInt64
}

public struct DeathView {
    public var dead: Set<ReferenceKey> = []
    public var counts: [FormID: Int] = [:]
}

public struct MarkerViewKey: Hashable {
    public let store: ObjectIdentifier
    public let markers: UInt64
    public let references: [ReferenceKey]
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
public struct ActorViewKey: Hashable {
    public let store: ObjectIdentifier
    public let writes: UInt64
    public let playerLevel: Int
    public let hasInventory: Bool
    public let actors: [ActorViewMember]
    /// Nil without a combat loop, where an NPC reports no action at all.
    public let phases: [ReferenceKey: CombatBehaviorPhase]?
}

public struct ActorViewMember: Hashable {
    public let holder: ActorValueHolder
    public let isDead: Bool
}
