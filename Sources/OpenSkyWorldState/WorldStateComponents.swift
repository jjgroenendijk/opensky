// Mutable world-state components (issue #159, roadmap item 10.1.2): the typed
// per-reference deltas that `WorldStateStore` keeps when runtime state deviates
// from what a plugin authored.
//
// Each component is its own value type rather than one wide "reference state"
// blob, so a module adds a component by declaring a type and its
// `WorldStateComponentKind` without reshaping the store: every store operation
// is written against `WorldStateComponent` and the erased
// `WorldStateComponentValue`, never against a fixed field list.
//
// Documented in docs/engine/runtime-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// Identity of one component slot on a reference.
///
/// A reference holds at most one value per kind, so this doubles as the
/// dictionary key inside `ReferenceStateDelta` and as the addressing token for
/// per-component reset and journal entries.
///
/// The set is open: the module that owns a component declares its kind in an
/// extension, for example `static let spellbook`. `order` fixes where the kind
/// sorts, so iteration, the change journal and a reset never depend on
/// dictionary ordering. Two kinds never share an order.
nonisolated public struct WorldStateComponentKind: Hashable, Comparable, Sendable {
    /// Stable name, printed by inspection surfaces.
    public let rawValue: String
    /// Position in the deterministic iteration order.
    public let order: Int

    public init(rawValue: String, order: Int) {
        self.rawValue = rawValue
        self.order = order
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.order < rhs.order
    }

    /// Runtime enable/disable, overriding the record's `initiallyDisabled`
    /// header flag.
    public static let enableState = Self(rawValue: "enableState", order: 0)
    /// Position, rotation and scale override, replacing the record's DATA and
    /// XSCL placement.
    public static let transform = Self(rawValue: "transform", order: 1)
    /// Activation bookkeeping: how often the reference was activated, whether
    /// it currently reads as open, and who activated it last.
    public static let activation = Self(rawValue: "activation", order: 2)
    /// Runtime deletion, which is not the same thing as the record's `deleted`
    /// header flag: this one is set while the game runs.
    public static let deletion = Self(rawValue: "deletion", order: 3)
    /// An object the running game placed in the world — a dropped item today,
    /// a summon later. The value type is `ReferenceSpawnState`. Unlike every
    /// other component this one does not modify a plugin placement; it *is*
    /// the placement, and only a generated `ReferenceKey` ever carries it.
    public static let spawn = Self(rawValue: "spawn", order: 5)
}

/// A value that can occupy one component slot.
///
/// Conformers are plain `Equatable`, `Sendable` value types. `erased` widens a
/// concrete component into the storage representation, and `init(erased:)`
/// narrows it back, returning nil when the value belongs to a different slot.
/// Both come from the extension below.
nonisolated public protocol WorldStateComponent: Equatable, Sendable {
    /// The slot this component type occupies.
    static var componentKind: WorldStateComponentKind { get }
}

nonisolated extension WorldStateComponent {
    /// This value widened into the erased storage representation.
    public var erased: WorldStateComponentValue {
        WorldStateComponentValue(self)
    }

    /// Narrows an erased value, or nil when it is a different component kind.
    public init?(erased: WorldStateComponentValue) {
        guard let value = erased.base as? Self else { return nil }
        self = value
    }

    fileprivate func isEqual(to other: any WorldStateComponent) -> Bool {
        (other as? Self) == self
    }
}

/// One component value with its concrete type erased.
///
/// This is the representation `ReferenceStateDelta` stores and the journal
/// records, so old/new pairs in the journal stay strongly typed without the
/// journal needing to be generic. The module that owns a component adds a
/// factory beside its kind, for example `static func spellbook(_:)`.
nonisolated public struct WorldStateComponentValue: Equatable, Sendable {
    public let base: any WorldStateComponent

    public init(_ value: some WorldStateComponent) {
        base = value
    }

    public var kind: WorldStateComponentKind {
        type(of: base).componentKind
    }

    /// The value as `type`, or nil when it is a different component.
    public func value<Component: WorldStateComponent>(as type: Component.Type) -> Component? {
        base as? Component
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.base.isEqual(to: rhs.base)
    }

    public static func enableState(_ value: ReferenceEnableState) -> Self {
        Self(value)
    }

    public static func transform(_ value: ReferenceTransformOverride) -> Self {
        Self(value)
    }

    public static func activation(_ value: ReferenceActivationState) -> Self {
        Self(value)
    }

    public static func deletion(_ value: ReferenceDeletionState) -> Self {
        Self(value)
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

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
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

    public init(isDeleted: Bool) {
        self.isDeleted = isDeleted
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

    /// Kinds present, in `WorldStateComponentKind.order` so that iteration
    /// never depends on dictionary ordering.
    public var sortedKinds: [WorldStateComponentKind] {
        components.keys.sorted()
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
