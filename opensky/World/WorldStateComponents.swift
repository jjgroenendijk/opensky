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
import simd

/// Identity of one component slot on a reference.
///
/// A reference holds at most one value per kind, so this doubles as the
/// dictionary key inside `ReferenceStateDelta` and as the addressing token for
/// per-component reset and journal entries. Adding a component in a later
/// milestone means adding a case here plus a conforming value type.
nonisolated enum WorldStateComponentKind: String, CaseIterable, Hashable, Sendable {
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
    /// `opensky/Inventory/InventoryComponent.swift` because it carries stack
    /// arithmetic of its own rather than being a plain field bag.
    case inventory
    /// An object the running game placed in the world — a dropped item today,
    /// a summon later (issue #177). The value type is `ReferenceSpawnState` in
    /// `opensky/World/SpawnedReference.swift`. Unlike every other component
    /// this one does not modify a plugin placement; it *is* the placement, and
    /// only a generated `ReferenceKey` ever carries it.
    case spawn
}

/// A value that can occupy one component slot.
///
/// Conformers are plain `Equatable`, `Sendable` value types. The two erasure
/// members are what let the store, the journal and the snapshot stay generic:
/// `erased` widens a concrete component into the storage representation, and
/// `init(erased:)` narrows it back, returning nil when the value belongs to a
/// different slot.
nonisolated protocol WorldStateComponent: Equatable, Sendable {
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
nonisolated enum WorldStateComponentValue: Equatable, Sendable {
    case enableState(ReferenceEnableState)
    case transform(ReferenceTransformOverride)
    case activation(ReferenceActivationState)
    case deletion(ReferenceDeletionState)
    case inventory(ReferenceInventoryState)
    case spawn(ReferenceSpawnState)

    var kind: WorldStateComponentKind {
        switch self {
        case .enableState: .enableState
        case .transform: .transform
        case .activation: .activation
        case .deletion: .deletion
        case .inventory: .inventory
        case .spawn: .spawn
        }
    }
}

// MARK: - Components

/// Whether a reference is currently enabled, overriding the record header's
/// `initiallyDisabled` flag. Papyrus `Enable()` / `Disable()` (M11) writes
/// exactly this component.
nonisolated struct ReferenceEnableState: WorldStateComponent, Hashable {
    var isEnabled: Bool

    static let enabled = ReferenceEnableState(isEnabled: true)
    static let disabled = ReferenceEnableState(isEnabled: false)

    static var componentKind: WorldStateComponentKind {
        .enableState
    }

    var erased: WorldStateComponentValue {
        .enableState(self)
    }

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .enableState(value) = erased else { return nil }
        self = value
    }
}

/// A full placement override: the REFR/ACHR DATA transform plus the XSCL
/// scale, which the records keep as separate fields and this component keeps
/// together because moving something at runtime touches both.
nonisolated struct ReferenceTransformOverride: WorldStateComponent {
    var placement: PlacedReference.Placement
    /// Uniform scale, matching XSCL semantics; 1 is "unscaled".
    var scale: Float

    static var componentKind: WorldStateComponentKind {
        .transform
    }

    var erased: WorldStateComponentValue {
        .transform(self)
    }

    var position: SIMD3<Float> {
        placement.position
    }

    var rotation: SIMD3<Float> {
        placement.rotation
    }

    init(placement: PlacedReference.Placement, scale: Float = 1) {
        self.placement = placement
        self.scale = scale
    }

    init(position: SIMD3<Float>, rotation: SIMD3<Float> = .zero, scale: Float = 1) {
        self.init(
            placement: PlacedReference.Placement(position: position, rotation: rotation),
            scale: scale
        )
    }

    init?(erased: WorldStateComponentValue) {
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
nonisolated struct ReferenceActivationState: WorldStateComponent, Hashable {
    var activationCount: UInt32
    var isOpen: Bool
    var lastActivator: ReferenceKey?

    /// Never activated: the value a reference implicitly has before anything
    /// touches it.
    static let untouched = ReferenceActivationState()

    static var componentKind: WorldStateComponentKind {
        .activation
    }

    var erased: WorldStateComponentValue {
        .activation(self)
    }

    var wasActivated: Bool {
        activationCount > 0
    }

    init(activationCount: UInt32 = 0, isOpen: Bool = false, lastActivator: ReferenceKey? = nil) {
        self.activationCount = activationCount
        self.isOpen = isOpen
        self.lastActivator = lastActivator
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .activation(value) = erased else { return nil }
        self = value
    }

    /// The state after one more activation by `activator`, toggling `isOpen`
    /// when `togglesOpen` is set (doors and containers) and leaving it alone
    /// otherwise.
    func activated(by activator: ReferenceKey? = nil, togglesOpen: Bool = false) -> Self {
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
nonisolated struct ReferenceDeletionState: WorldStateComponent, Hashable {
    var isDeleted: Bool

    static let deleted = ReferenceDeletionState(isDeleted: true)
    static let notDeleted = ReferenceDeletionState(isDeleted: false)

    static var componentKind: WorldStateComponentKind {
        .deletion
    }

    var erased: WorldStateComponentValue {
        .deletion(self)
    }

    init(isDeleted: Bool) {
        self.isDeleted = isDeleted
    }

    init?(erased: WorldStateComponentValue) {
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
nonisolated struct ReferenceStateDelta: Equatable, Sendable {
    /// Component values by slot. Never contains an entry the store considers
    /// clean: clearing the last component removes the whole delta.
    private(set) var components: [WorldStateComponentKind: WorldStateComponentValue]
    /// Cell the most recent mutation was recorded under, for per-cell dirty
    /// counts.
    private(set) var cell: CellSceneLocation?

    init(
        components: [WorldStateComponentKind: WorldStateComponentValue] = [:],
        cell: CellSceneLocation? = nil
    ) {
        self.components = components
        self.cell = cell
    }

    var isEmpty: Bool {
        components.isEmpty
    }

    /// Kinds present, in `WorldStateComponentKind.allCases` order so that
    /// iteration never depends on dictionary ordering.
    var sortedKinds: [WorldStateComponentKind] {
        WorldStateComponentKind.allCases.filter { components[$0] != nil }
    }

    subscript(kind: WorldStateComponentKind) -> WorldStateComponentValue? {
        components[kind]
    }

    /// The stored value for `type`, or nil when that slot is clean.
    func component<Component: WorldStateComponent>(_ type: Component.Type) -> Component? {
        guard let erased = components[Component.componentKind] else { return nil }
        return Component(erased: erased)
    }

    /// Stores `value`, returning the value it replaced.
    @discardableResult
    mutating func set(_ value: WorldStateComponentValue) -> WorldStateComponentValue? {
        let previous = components[value.kind]
        components[value.kind] = value
        return previous
    }

    /// Removes the value in `kind`, returning what was there.
    @discardableResult
    mutating func clear(_ kind: WorldStateComponentKind) -> WorldStateComponentValue? {
        components.removeValue(forKey: kind)
    }

    mutating func record(cell: CellSceneLocation?) {
        if let cell {
            self.cell = cell
        }
    }
}
