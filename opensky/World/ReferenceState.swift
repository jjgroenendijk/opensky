// Plugin baseline plus runtime delta, resolved (issue #159, roadmap item
// 10.1.2). This is the read side of `WorldStateStore`: the baseline is derived
// from the decoded record every time it is asked for, never cached, so a store
// delta can never go stale against a reloaded plugin.
//
// Applying a resolved state during a cell build is issue #160's work; this type
// only computes it.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// The state of one reference: what the plugin authored, with any runtime
/// deltas laid over the top.
///
/// Construct it from a `RuntimeReferenceEntry` for the plugin baseline, then
/// call `applying(_:)` with the store's delta. `overriddenKinds` reports which
/// slots the delta supplied, so a caller can tell "disabled because a script
/// disabled it" from "disabled because the record says so".
nonisolated struct ReferenceState: Equatable, Sendable {
    let key: ReferenceKey
    var enableState: ReferenceEnableState
    var transform: ReferenceTransformOverride
    var activation: ReferenceActivationState
    var deletion: ReferenceDeletionState
    /// Slots whose value came from a runtime delta rather than the record.
    private(set) var overriddenKinds: Set<WorldStateComponentKind> = []

    /// True when at least one slot deviates from the record.
    var isDirty: Bool {
        !overriddenKinds.isEmpty
    }

    /// The plugin baseline for `entry`, re-derived from its decoded record.
    ///
    /// Two gaps are deliberate and belong to issue #160, which is where deltas
    /// start being applied at build time:
    ///
    /// * `PlacedReference` does not decode the record header, so a REFR's
    ///   `initiallyDisabled` flag is not visible here and every REFR baselines
    ///   as enabled. `PlacedActor` does carry the flag and is honoured.
    /// * Neither placement type carries the header's `deleted` flag, so the
    ///   deletion baseline is always "not deleted". That flag means the plugin
    ///   removed the record, which is a load-time concern rather than a runtime
    ///   one.
    init(baseline entry: RuntimeReferenceEntry) {
        key = entry.key
        switch entry.record {
        case let .reference(reference):
            enableState = .enabled
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
    func applying(_ delta: ReferenceStateDelta?) -> Self {
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
    var isVisible: Bool {
        enableState.isEnabled && !deletion.isDeleted
    }
}
