// Reconciling a clip's children across a timeline jump (milestone 8.3.2 phase
// 3), replacing the phase-2 shortcut that tore the whole child list down and
// replayed every frame from scratch.
//
// The shortcut was wrong in a way that only shows once ActionScript is running.
// A display list is the accumulation of every frame before it and the control
// tags carry no undo, so computing the destination state does mean replaying
// from frame 1 — but *applying* that state must keep the instances that survive
// it. Flash keeps an instance when the destination frame places the same
// character at the same depth, which is why a clip can attach a handler to a
// child, jump its own timeline, and still find the handler there.
//
// Vanilla depends on it. `tweenmenu.swf` wires `onRollOver` and `onMouseDown`
// onto its four input rectangles in `InitExtensions`, then opens itself with a
// `gotoAndPlay` that lands two frames further on. Rebuilding from scratch
// discarded both handlers and left the menu unclickable; reconciling keeps them.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 3 "The
// display list" — the place / modify / replace / remove rules for a depth, which
// are what the accumulation below implements.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// The cumulative display-list state at `index`, keyed by depth. This is the
    /// same accumulation `SWFDisplayListBuilder` performs for frame 1, kept as
    /// `SWFPlacement` rather than `SWFPlacedObject` so a placement's CLIPACTIONS
    /// handlers survive the walk.
    func accumulatedPlacements(
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
        if let ratio = placement.ratio {
            existing.ratio = ratio
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
    func reconcile(to index: Int, of node: SWFDisplayObject, frames: [SWFTimelineFrame]) {
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
