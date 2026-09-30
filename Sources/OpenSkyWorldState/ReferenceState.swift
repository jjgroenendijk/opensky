// Plugin baseline plus runtime delta, resolved. The read side of
// `WorldStateStore`: the baseline is re-derived from the record on every ask,
// so a delta cannot go stale against a reloaded plugin.
// See docs/engine/runtime-state.md.

import Foundation
import OpenSkyFormatsESM

/// The state of one reference: the plugin baseline with runtime deltas on top.
/// `overriddenKinds` names the slots the delta supplied, so a caller can tell
/// a script disable from a record disable.
nonisolated public struct ReferenceState: Equatable, Sendable {
    public var enableState: ReferenceEnableState
    public var transform: ReferenceTransformOverride
    public var activation: ReferenceActivationState
    public var deletion: ReferenceDeletionState
    /// Slots whose value came from a runtime delta rather than the record.
    public private(set) var overriddenKinds: Set<WorldStateComponentKind> = []

    /// True when at least one slot deviates from the record.
    public var isDirty: Bool {
        !overriddenKinds.isEmpty
    }

    /// The plugin baseline for `entry`, re-derived from its decoded record.
    /// Deletion is always "not deleted": the header flag is a load-time concern.
    public init(baseline entry: RuntimeReferenceEntry) {
        switch entry.record {
        case let .reference(reference):
            enableState = ReferenceEnableState(isEnabled: !reference.isInitiallyDisabled)
            transform = ReferenceTransformOverride(
                placement: reference.placement,
                scale: reference.scale
            )
        case let .actor(actor):
            enableState = ReferenceEnableState(isEnabled: !actor.isInitiallyDisabled)
            transform = ReferenceTransformOverride(
                placement: actor.placement,
                scale: actor.scale
            )
        }
        activation = .untouched
        deletion = .notDeleted
    }

    /// This baseline with `delta`'s components laid over it. A nil or empty
    /// delta returns the baseline unchanged.
    public func applying(_ delta: ReferenceStateDelta?) -> Self {
        guard let delta, !delta.isEmpty else { return self }
        var resolved = self
        if let value = delta.component(ReferenceEnableState.self) {
            resolved.enableState = value
            resolved.overriddenKinds.insert(.enableState)
        }
        if let value = delta.component(ReferenceTransformOverride.self) {
            resolved.transform = value
            resolved.overriddenKinds.insert(.transform)
        }
        if let value = delta.component(ReferenceActivationState.self) {
            resolved.activation = value
            resolved.overriddenKinds.insert(.activation)
        }
        if let value = delta.component(ReferenceDeletionState.self) {
            resolved.deletion = value
            resolved.overriddenKinds.insert(.deletion)
        }
        return resolved
    }

    /// Whether this reference should be drawn at all: deleted-at-runtime and
    /// disabled objects both drop out.
    public var isVisible: Bool {
        enableState.isEnabled && !deletion.isDeleted
    }
}
