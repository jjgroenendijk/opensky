// Reads of one reference: its live state and its links.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge.ReferenceReads {
    /// The enabled flag follows a resident `XESP` parent, as the cell build does. A
    /// scripted move shows its live pose.
    public func referenceState(for key: ReferenceKey) -> ReferenceState? {
        guard let entry = bridge.ports.references?.referenceEntry(key: key) else { return nil }
        var state = bridge.worldState.resolvedState(for: entry)
        if let move = bridge.runState.translations[key] {
            state.transform = move.pose(scale: state.transform.scale)
        }
        guard entry.enableParent != nil else { return state }
        let store = bridge.worldState
        let resolver = EnableParentResolver(
            delta: { store.delta(for: $0) },
            parent: { [references = bridge.ports.references] in
                references?.referenceEntry(formID: $0)
            }
        )
        state.enableState = ReferenceEnableState(isEnabled: resolver.isEnabled(entry))
        return state
    }

    /// An ACHR keeps its links in its details, a REFR in its own field.
    public func linkedReferences(of key: ReferenceKey) -> [LinkedReference] {
        guard let entry = bridge.ports.references?.referenceEntry(key: key) else { return [] }
        return entry.placedReference?.linkedReferences
            ?? entry.placedActor?.details.linkedReferences ?? []
    }

    public func baseObject(of key: ReferenceKey) -> FormID? {
        guard let entry = bridge.ports.references?.referenceEntry(key: key) else { return nil }
        return entry.placedReference?.base ?? entry.placedActor?.base
    }

    /// Resolves through the session's master-list resolver, then the reference index for
    /// synthetic sessions. One resolver per session, as in the cell builder, so another
    /// plugin's FormID spelling resolves wrongly.
    /// The load-order FormID of `key`, or nil for a key outside the load order.
    public func localFormID(of key: ReferenceKey) -> FormID? {
        guard case let .plugin(plugin, objectID) = key else { return nil }
        return bridge.formIDResolver?.localFormID(of: ResolvedFormID(
            plugin: plugin,
            objectID: objectID
        ))
    }

    public func referenceKey(forFormID formID: FormID) -> ReferenceKey? {
        if let formIDResolver = bridge.formIDResolver, let key = ReferenceKey.resolve(
            formID,
            using: formIDResolver
        ) {
            return key
        }
        return bridge.ports.references?.referenceEntry(formID: formID)?.key
    }

    public func placedReference(for key: ReferenceKey) -> PlacedReference? {
        bridge.ports.references?.referenceEntry(key: key)?.placedReference
    }

    public func lockState(for key: ReferenceKey) -> ReferenceLockState? {
        ReferenceLockState.resolve(
            baseline: placedReference(for: key)?.lock,
            delta: bridge.worldState.component(ReferenceLockState.self, for: key)
        )
    }
}
