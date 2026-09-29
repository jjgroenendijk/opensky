// Reconciles a clip's children across a timeline jump. The destination state
// is replayed from frame 1, but an instance the destination places with the
// same character at the same depth is kept, as Flash does, so handlers
// attached to it survive (SWF spec v19, ch. 3).

import Foundation

nonisolated extension SWFMovieRuntime {
    /// The cumulative display-list state at `index`, keyed by depth. This is the
    /// same accumulation `SWFDisplayListBuilder` performs for frame 1, kept as
    /// `SWFPlacement` rather than `SWFPlacedObject` so a placement's CLIPACTIONS
    /// handlers survive the walk.
    public func accumulatedPlacements(
        to index: Int,
        frames: [SWFTimelineFrame]
    ) -> [UInt16: SWFPlacement] {
        var state: [UInt16: SWFPlacement] = [:]
        for step in 0 ... min(index, frames.count - 1) {
            for entry in frames[step].steps {
                switch entry {
                case let .place(placement):
                    merge(placement, into: &state)
                case let .remove(removal):
                    state[removal.depth] = nil
                }
            }
        }
        return state
    }

    /// Place / modify / replace at one depth. A placement with no character id
    /// modifies the occupant; one that carries a character id and no move flag
    /// starts a fresh instance; one that carries both replaces the character and
    /// keeps the occupant's state, which is the behavior the frame-1 builder
    /// already implements.
    private func merge(_ placement: SWFPlacement, into state: inout [UInt16: SWFPlacement]) {
        guard var existing = state[placement.depth] else {
            if placement.characterId != nil {
                state[placement.depth] = placement
            }
            return
        }
        guard placement.isMove || placement.characterId == nil else {
            state[placement.depth] = placement
            return
        }
        if let characterId = placement.characterId {
            existing.characterId = characterId
        }
        if let matrix = placement.matrix {
            existing.matrix = matrix
        }
        if let colorTransform = placement.colorTransform {
            existing.colorTransform = colorTransform
        }
        if let name = placement.name {
            existing.name = name
        }
        if let clipDepth = placement.clipDepth {
            existing.clipDepth = clipDepth
        }
        if let clipActions = placement.clipActions {
            existing.clipActions = clipActions
        }
        state[placement.depth] = existing
    }

    /// Brings a clip's children to the destination frame's state: instances the
    /// destination keeps are kept and re-applied, instances it does not are
    /// unloaded, and depths it introduces are instantiated and brought up.
    public func reconcile(to index: Int, of node: SWFDisplayObject, frames: [SWFTimelineFrame]) {
        let target = accumulatedPlacements(to: index, frames: frames)
        for child in node.children where target[child.depth] == nil {
            dispatchPlacementLifecycle(child, phase: .unloaded)
            node.removeChild(atDepth: child.depth)
        }
        for depth in target.keys.sorted() {
            guard let placement = target[depth] else {
                continue
            }
            let existing = node.child(atDepth: depth)
            if let existing, existing.characterId == placement.characterId {
                apply(placement, to: existing)
                continue
            }
            if let existing {
                dispatchPlacementLifecycle(existing, phase: .unloaded)
            }
            guard
                let characterId = placement.characterId,
                let fresh = makeDisplayObject(characterId: characterId)
            else {
                continue
            }
            apply(placement, to: fresh)
            node.addChild(fresh, atDepth: depth)
            bringUp(fresh)
        }
    }
}
