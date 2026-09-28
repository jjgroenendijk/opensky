// Mutable world-state components (issue #159, roadmap item 10.1.2): the typed
// per-reference deltas that `WorldStateStore` keeps when runtime state deviates
// from what a plugin authored.
//
// Each component is its own value type rather than one wide "reference state"
// blob, so a later milestone adds inventory or actor values by adding a type
// and a `WorldStateComponentKind` case without reshaping the store: every
// store operation is written against `WorldStateComponent` and the erased
// `WorldStateComponentValue`, never against a fixed field list. Issue #176
// (inventory) was the first milestone to take that route and needed no change
// to the store at all.
//
// Documented in docs/engine/runtime-state.md.

import Foundation
import OpenSkyFormats
import simd

/// Identity of one component slot on a reference.
///
/// A reference holds at most one value per kind, so this doubles as the
/// dictionary key inside `ReferenceStateDelta` and as the addressing token for
/// per-component reset and journal entries. Adding a component in a later
/// milestone means adding a case here plus a conforming value type.
nonisolated public enum WorldStateComponentKind: String, CaseIterable, Hashable, Sendable {
    /// Runtime enable/disable, overriding the record's `initiallyDisabled`
    /// header flag.
    case enableState
    /// Position, rotation and scale override, replacing the record's DATA and
    /// XSCL placement.
    case transform
    /// Activation bookkeeping: how often the reference was activated, whether
    /// it currently reads as open, and who activated it last.
    case activation
    /// Runtime deletion, which is not the same thing as the record's `deleted`
    /// header flag: this one is set while the game runs.
    case deletion
    /// Everything one owner holds, plus its equipped set (issue #176). The
    /// value type is `ReferenceInventoryState`, which lives in
    /// `Sources/OpenSkyEngine/Inventory/InventoryComponent.swift` because it carries stack
    /// arithmetic of its own rather than being a plain field bag.
    case inventory
    /// An object the running game placed in the world — a dropped item today,
    /// a summon later (issue #177). The value type is `ReferenceSpawnState` in
    /// `Sources/OpenSkyEngine/World/State/SpawnedReference.swift`. Unlike every other component
    /// this one does not modify a plugin placement; it *is* the placement, and
    /// only a generated `ReferenceKey` ever carries it.
    case spawn
    /// One quest's running, stage and objective state (issue #182). The value
    /// type is `QuestRuntimeState` in
    /// `Sources/OpenSkyEngine/Quests/QuestStateComponent.swift`. Like `spawn` this one does
    /// not modify a placement: it is keyed by a QUST base record's
    /// `ReferenceKey`, the same way `GlobalStore` keys a GLOB override, because
    /// a quest is not placed anywhere and belongs to no cell.
    case quest
    /// One quest's filled reference aliases (issue #183). The value type is
    /// `QuestAliasState` in `Sources/OpenSkyEngine/Quests/QuestAliasComponent.swift`, keyed
    /// by the same QUST `ReferenceKey` the `quest` slot uses. It is a slot of
    /// its own because the two have different lifetimes: stage and objective
    /// state survives a stop, while the alias table is cleared by one.
    case questAliases
    /// One actor's current health, magicka and stamina (issue #194). The value
    /// type is `ActorValueState` in
    /// `Sources/OpenSkyEngine/Actors/ActorValueComponent.swift`. Current values only: the
    /// maximums re-derive from the RACE, CLAS and NPC_ records through
    /// `ActorValueResolver`, exactly as an inventory baseline re-derives from
    /// its CNTO list.
    case actorValues
    /// One actor's death and the resting transform its ragdoll settled at
    /// (issue #197). The value type is `ActorDeathState` in
    /// `Sources/OpenSkyEngine/Actors/ActorDeathComponent.swift`. A slot of its own rather than
    /// a field on `actorValues` because the two have different lifetimes: a
    /// current-health float is rewritten every regeneration step, while death is
    /// a latch nothing but a resurrection clears.
    case death
    /// One actor's hostility toward the player (issue #374). The value type is
    /// `ActorCombatState` in `Sources/OpenSkyEngine/Actors/ActorCombatComponent.swift`. A slot
    /// of its own beside `actorValues` and `death` for the same lifetime reason
    /// those two are separate: hostility changes on a handful of events, while
    /// the values beside it are rewritten sixty times a second.
    case combat
    /// One dialogue response's said-state (issue #426). The value type is
    /// `DialogueRuntimeState` in
    /// `Sources/OpenSkyEngine/Dialogue/DialogueStateComponent.swift`. Like `quest` it
    /// modifies no placement: it is keyed by an INFO base record's
    /// `ReferenceKey`, because a response is not placed anywhere and belongs to
    /// no cell.
    case dialogue
    /// Every magic effect currently acting on one actor (issue #469). The value
    /// type is `ActiveEffectState` in
    /// `Sources/OpenSkyEngine/Magic/ActiveEffectComponent.swift`. A slot of its own
    /// beside `actorValues` for the lifetime reason `death` and `combat` are
    /// separate slots: the values beside it are rewritten sixty times a second,
    /// while an effect list changes only when something is applied, expires or
    /// is dispelled.
    case activeEffects
    /// One actor's known spells, read tomes, readied hands and spent greater
    /// powers (issue #470). The value type is `SpellbookState` in
    /// `Sources/OpenSkyEngine/Magic/SpellbookComponent.swift`. A slot of its own for
    /// the reason `activeEffects` is one: everything in it changes on a player
    /// action, never per frame. The four fields share the slot rather than
    /// splitting further because a readied hand must name a known spell, and
    /// only one component can enforce that in a single write.
    case spellbook
    /// One owner's enchanted items: charge left per weapon, and the constant
    /// effects each worn piece established (issue #472). The value type is
    /// `EnchantedItemState` in
    /// `Sources/OpenSkyEngine/Magic/EnchantedItemComponent.swift`. A slot of its own
    /// rather than fields on `inventory` for the lifetime reason `activeEffects`
    /// is separate from `actorValues`: the inventory component is rewritten by
    /// every take, drop and equip, while charge moves only when an enchanted
    /// weapon actually lands a hit.
    case enchantedItems
    /// The perks one actor owns (issue #497). The value type is `PerkState` in
    /// `Sources/OpenSkyEngine/Progression/PerkComponent.swift`. A slot of its own for
    /// the reason `spellbook` is one: owning a perk changes on a level-up, a
    /// script call or an actor's first appearance, never per frame, while the
    /// actor values a perk goes on to modify are rewritten sixty times a
    /// second.
    case perks
    /// Every faction one actor currently belongs to, and the rank it holds in
    /// each (issue #503). The value type is `ActorFactionState` in
    /// `Sources/OpenSkyEngine/Factions/ActorFactionComponent.swift`. A slot of its own
    /// for the reason `perks` is one: a membership moves on a quest stage or a
    /// script call, while the actor values beside it are rewritten sixty times
    /// a second. It is also the input to the hostility derivation, which is why
    /// it must be a component and not a re-read of the NPC_ record: an actor
    /// the player has joined to a faction has to stay joined across a reload.
    case factions
    /// Relationship ranks a script has set between one actor and others
    /// (issue #508). The value type is `ActorRelationshipState` in
    /// `Sources/OpenSkyEngine/Factions/ActorRelationshipComponent.swift`. A slot of its
    /// own beside `factions` because the two are different facts with the same
    /// lifetime: what an actor *belongs to*, and what it *is to somebody else*.
    /// The Creation Kit says outright that "relationships override factions"
    /// (<https://ck.uesp.net/wiki/Relationship>), so they cannot share a slot
    /// and still be resolved in that order.
    case relationships
    /// The player's character level, banked character experience, unspent perk
    /// points and attribute-pick history (issue #499). The value type is
    /// `PlayerProgressState` in
    /// `Sources/OpenSkyEngine/Progression/PlayerProgressState.swift`. Like `quest` it
    /// modifies no placement and belongs to no cell: it is keyed by
    /// `ReferenceKey.player`, who has no record in this engine. A slot of its
    /// own beside `perks` because the two answer different questions — how many
    /// points are left to spend, and which perks those points already bought.
    case playerProgress
    /// What one actor owes each crime faction, and how many of each crime it
    /// has committed against them (issue #504). The value type is
    /// `CrimeLedgerState` in
    /// `Sources/OpenSkyEngine/Crime/CrimeLedgerComponent.swift`. Like `playerProgress`
    /// it modifies no placement and belongs to no cell in practice: it is keyed
    /// by the perpetrator, which is `ReferenceKey.player` for every path this
    /// milestone builds. A slot of its own beside `factions` for the reason
    /// `perks` is one — a bounty moves when a crime is witnessed, while the
    /// actor values beside it are rewritten sixty times a second.
    case crimeLedger
}

/// A value that can occupy one component slot.
///
/// Conformers are plain `Equatable`, `Sendable` value types. The two erasure
/// members are what let the store, the journal and the snapshot stay generic:
/// `erased` widens a concrete component into the storage representation, and
/// `init(erased:)` narrows it back, returning nil when the value belongs to a
/// different slot.
nonisolated public protocol WorldStateComponent: Equatable, Sendable {
    /// The slot this component type occupies.
    static var componentKind: WorldStateComponentKind { get }
    /// This value widened into the erased storage representation.
    var erased: WorldStateComponentValue { get }
    /// Narrows an erased value, or nil when it is a different component kind.
    init?(erased: WorldStateComponentValue)
}

/// One component value with its concrete type erased.
///
/// This is the representation `ReferenceStateDelta` stores and the journal
/// records, so old/new pairs in the journal stay strongly typed without the
/// journal needing to be generic.
nonisolated public enum WorldStateComponentValue: Equatable, Sendable {
    case enableState(ReferenceEnableState)
    case transform(ReferenceTransformOverride)
    case activation(ReferenceActivationState)
    case deletion(ReferenceDeletionState)
    case inventory(ReferenceInventoryState)
    case spawn(ReferenceSpawnState)
    case quest(QuestRuntimeState)
    case questAliases(QuestAliasState)
    case actorValues(ActorValueState)
    case death(ActorDeathState)
    case combat(ActorCombatState)
    case dialogue(DialogueRuntimeState)
    case activeEffects(ActiveEffectState)
    case spellbook(SpellbookState)
    case enchantedItems(EnchantedItemState)
    case perks(PerkState)
    case factions(ActorFactionState)
    case relationships(ActorRelationshipState)
    case playerProgress(PlayerProgressState)
    case crimeLedger(CrimeLedgerState)

    public var kind: WorldStateComponentKind {
        switch self {
        case .enableState: .enableState
        case .transform: .transform
        case .activation: .activation
        case .deletion: .deletion
        case .inventory: .inventory
        case .spawn: .spawn
        case .quest: .quest
        case .questAliases: .questAliases
        case .actorValues: .actorValues
        case .death: .death
        case .combat: .combat
        case .dialogue: .dialogue
        case .activeEffects: .activeEffects
        case .spellbook: .spellbook
        case .enchantedItems: .enchantedItems
        case .perks: .perks
        case .factions: .factions
        case .relationships: .relationships
        case .playerProgress: .playerProgress
        case .crimeLedger: .crimeLedger
        }
    }
}

// MARK: - Components

/// Whether a reference is currently enabled, overriding the record header's
/// `initiallyDisabled` flag. Papyrus `Enable()` / `Disable()` (M11) writes
/// exactly this component.
nonisolated public struct ReferenceEnableState: WorldStateComponent, Hashable, Sendable {
    public var isEnabled: Bool

    public static let enabled = ReferenceEnableState(isEnabled: true)
    public static let disabled = ReferenceEnableState(isEnabled: false)

    public static var componentKind: WorldStateComponentKind {
        .enableState
    }

    public var erased: WorldStateComponentValue {
        .enableState(self)
    }

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public init?(erased: WorldStateComponentValue) {
        guard case let .enableState(value) = erased else { return nil }
        self = value
    }
}

/// A full placement override: the REFR/ACHR DATA transform plus the XSCL
/// scale, which the records keep as separate fields and this component keeps
/// together because moving something at runtime touches both.
nonisolated public struct ReferenceTransformOverride: WorldStateComponent, Sendable {
    public var placement: PlacedReference.Placement
    /// Uniform scale, matching XSCL semantics; 1 is "unscaled".
    public var scale: Float

    public static var componentKind: WorldStateComponentKind {
        .transform
    }

    public var erased: WorldStateComponentValue {
        .transform(self)
    }

    public var position: SIMD3<Float> {
        placement.position
    }

    public var rotation: SIMD3<Float> {
        placement.rotation
    }

    public init(placement: PlacedReference.Placement, scale: Float = 1) {
        self.placement = placement
        self.scale = scale
    }

    public init(position: SIMD3<Float>, rotation: SIMD3<Float> = .zero, scale: Float = 1) {
        self.init(
            placement: PlacedReference.Placement(position: position, rotation: rotation),
            scale: scale
        )
    }

    public init?(erased: WorldStateComponentValue) {
        guard case let .transform(value) = erased else { return nil }
        self = value
    }
}

/// Activation bookkeeping for one reference.
///
/// `activationCount` is the raw number of successful activations, which is what
/// a "has the player ever opened this container" check needs. `isOpen` is the
/// typed open/closed marker doors and containers read. `lastActivator` is the
/// reference that most recently activated this one, which M11's `OnActivate`
/// hands to script code as its `akActionRef` argument.
nonisolated public struct ReferenceActivationState: WorldStateComponent, Hashable, Sendable {
    public var activationCount: UInt32
    public var isOpen: Bool
    public var lastActivator: ReferenceKey?

    /// Never activated: the value a reference implicitly has before anything
    /// touches it.
    public static let untouched = ReferenceActivationState()

    public static var componentKind: WorldStateComponentKind {
        .activation
    }

    public var erased: WorldStateComponentValue {
        .activation(self)
    }

    public var wasActivated: Bool {
        activationCount > 0
    }

    public init(
        activationCount: UInt32 = 0,
        isOpen: Bool = false,
        lastActivator: ReferenceKey? = nil
    ) {
        self.activationCount = activationCount
        self.isOpen = isOpen
        self.lastActivator = lastActivator
    }

    public init?(erased: WorldStateComponentValue) {
        guard case let .activation(value) = erased else { return nil }
        self = value
    }

    /// The state after one more activation by `activator`, toggling `isOpen`
    /// when `togglesOpen` is set (doors and containers) and leaving it alone
    /// otherwise.
    public func activated(by activator: ReferenceKey? = nil, togglesOpen: Bool = false) -> Self {
        ReferenceActivationState(
            activationCount: activationCount &+ 1,
            isOpen: togglesOpen ? !isOpen : isOpen,
            lastActivator: activator ?? lastActivator
        )
    }
}

/// Runtime deletion. Distinct from the record header's `deleted` flag, which
/// says the plugin itself removed the record: this component says the running
/// game removed the object, and clearing it restores the plugin's placement.
nonisolated public struct ReferenceDeletionState: WorldStateComponent, Hashable, Sendable {
    public var isDeleted: Bool

    public static let deleted = ReferenceDeletionState(isDeleted: true)
    public static let notDeleted = ReferenceDeletionState(isDeleted: false)

    public static var componentKind: WorldStateComponentKind {
        .deletion
    }

    public var erased: WorldStateComponentValue {
        .deletion(self)
    }

    public init(isDeleted: Bool) {
        self.isDeleted = isDeleted
    }

    public init?(erased: WorldStateComponentValue) {
        guard case let .deletion(value) = erased else { return nil }
        self = value
    }
}

// MARK: - Delta

/// Every runtime deviation recorded for one reference.
///
/// A delta holds at most one value per `WorldStateComponentKind`, plus the cell
/// the most recent mutation was made under. The store outlives cell eviction,
/// so the cell is remembered here rather than looked up: by the time a sidebar
/// asks "how many dirty references does Whiterun have", the cell may not be
/// resident any more. It is optional because a caller that has no meaningful
/// cell — a persistent reference mutated by a script with no scene loaded —
/// must still be able to record a delta.
nonisolated public struct ReferenceStateDelta: Equatable, Sendable {
    /// Component values by slot. Never contains an entry the store considers
    /// clean: clearing the last component removes the whole delta.
    public private(set) var components: [WorldStateComponentKind: WorldStateComponentValue]
    /// Cell the most recent mutation was recorded under, for per-cell dirty
    /// counts.
    public private(set) var cell: CellSceneLocation?

    public init(
        components: [WorldStateComponentKind: WorldStateComponentValue] = [:],
        cell: CellSceneLocation? = nil
    ) {
        self.components = components
        self.cell = cell
    }

    public var isEmpty: Bool {
        components.isEmpty
    }

    /// Kinds present, in `WorldStateComponentKind.allCases` order so that
    /// iteration never depends on dictionary ordering.
    public var sortedKinds: [WorldStateComponentKind] {
        WorldStateComponentKind.allCases.filter { components[$0] != nil }
    }

    public subscript(kind: WorldStateComponentKind) -> WorldStateComponentValue? {
        components[kind]
    }

    /// The stored value for `type`, or nil when that slot is clean.
    public func component<Component: WorldStateComponent>(_ type: Component.Type) -> Component? {
        guard let erased = components[Component.componentKind] else { return nil }
        return Component(erased: erased)
    }

    /// Stores `value`, returning the value it replaced.
    @discardableResult
    public mutating func set(_ value: WorldStateComponentValue) -> WorldStateComponentValue? {
        let previous = components[value.kind]
        components[value.kind] = value
        return previous
    }

    /// Removes the value in `kind`, returning what was there.
    @discardableResult
    public mutating func clear(_ kind: WorldStateComponentKind) -> WorldStateComponentValue? {
        components.removeValue(forKey: kind)
    }

    public mutating func record(cell: CellSceneLocation?) {
        if let cell {
            self.cell = cell
        }
    }
}
