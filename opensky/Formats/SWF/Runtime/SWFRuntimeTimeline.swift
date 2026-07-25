// Timeline execution for the runtime display list (milestone 8.3.2 phase 2):
// entering a frame, applying that frame's control tags, running its DoAction
// blocks, and the four goto forms `AS2Host.perform` routes here.
//
// Stepping forward by one frame applies only that frame's control tags, which
// is what a player does. Any other jump accumulates the destination state from
// frame 1 — a display list is the sum of every step before it and the tags carry
// no undo — and then reconciles the live children against it, keeping every
// instance the destination frame still places at the same depth (see
// `SWFRuntimeGoto.swift`). The destination frame's DoAction blocks run either
// way; the skipped frames' do not, matching how `gotoAndStop` behaves in Flash.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 3 "The
// display list" (place/modify/replace/remove at a depth) and chapter 5
// "Actions" — "ActionPlay", "ActionStop", "ActionGotoFrame", "ActionGoToLabel".

import Foundation

nonisolated extension SWFMovieRuntime {
    /// The frames a node actually decoded. A sprite's declared `FrameCount` can
    /// exceed them, so indexing uses this and `_totalframes` uses the
    /// declaration.
    func frames(of node: SWFDisplayObject) -> [SWFTimelineFrame] {
        node.timeline?.frames ?? []
    }

    /// Moves `node`'s playhead to `index` and executes that frame.
    func enterFrame(_ index: Int, of node: SWFDisplayObject) {
        let frames = frames(of: node)
        guard node.isClip, !frames.isEmpty else {
            return
        }
        let target = min(max(0, index), frames.count - 1)
        if target == node.currentFrame + 1 {
            apply(frame: frames[target], to: node)
        } else if target != node.currentFrame {
            reconcile(to: target, of: node, frames: frames)
        }
        node.currentFrame = target
        markDirty()
        runActions(of: frames[target], on: node)
    }

    /// `gotoAndStop` / `gotoAndPlay` by zero-based frame index.
    func gotoFrame(_ index: Int, of node: SWFDisplayObject, play: Bool) {
        node.isPlaying = play
        enterFrame(index, of: node)
    }

    /// `gotoAndStop("label")` / `ActionGoToLabel`. An unknown label leaves the
    /// playhead alone and lands in the tally, never throws.
    func gotoLabel(_ label: String, of node: SWFDisplayObject, play: Bool) {
        guard let index = node.timeline?.frameIndex(forLabel: label) else {
            runtime.noteMissing("gotoAndStop(\(label))")
            node.isPlaying = play
            return
        }
        gotoFrame(index, of: node, play: play)
    }

    /// The AS2 timeline opcodes, once the host resolved their target.
    func perform(_ command: AS2TimelineCommand, on node: SWFDisplayObject) {
        switch command {
        case .stop:
            node.isPlaying = false
            markDirty()
        case .play:
            node.isPlaying = true
            markDirty()
        case let .gotoFrame(number):
            gotoFrame(number, of: node, play: node.isPlaying)
        case let .gotoLabel(label):
            gotoLabel(label, of: node, play: node.isPlaying)
        }
    }

    // MARK: - Frame execution

    private func apply(frame: SWFTimelineFrame, to node: SWFDisplayObject) {
        for step in frame.steps {
            switch step {
            case let .place(placement):
                place(placement, into: node)
            case let .remove(removal):
                // Unload is dispatched while the child is still attached, so
                // `_root` and `_parent` still resolve inside the handler.
                if let removed = node.child(atDepth: removal.depth) {
                    dispatchPlacementLifecycle(removed, phase: .unloaded)
                }
                node.removeChild(atDepth: removal.depth)
            }
        }
    }

    private func runActions(of frame: SWFTimelineFrame, on node: SWFDisplayObject) {
        guard !frame.actions.isEmpty else {
            return
        }
        guard gotoDepth < SWFMovieRuntime.maximumGotoDepth else {
            // A frame action that jumps its own clip re-enters this path; the
            // dropped blocks are counted rather than silently skipped.
            noteDroppedFrameActions(frame.actions.count)
            return
        }
        gotoDepth += 1
        defer { gotoDepth -= 1 }
        for block in frame.actions {
            runtime.execute(block, target: node.object)
        }
    }

    // MARK: - Placement

    /// PlaceObject semantics against a live tree: no character id plus
    /// `PlaceFlagMove` modifies the occupant, both replaces the character while
    /// keeping the occupant's state, and neither places a fresh instance.
    private func place(_ placement: SWFPlacement, into parent: SWFDisplayObject) {
        let existing = parent.child(atDepth: placement.depth)
        guard let characterId = placement.characterId else {
            guard placement.isMove, let existing else {
                return
            }
            apply(placement, to: existing)
            return
        }
        if placement.isMove, let existing, existing.characterId == characterId {
            apply(placement, to: existing)
            return
        }
        guard let node = makeDisplayObject(characterId: characterId) else {
            return
        }
        if placement.isMove, let existing {
            node.matrix = existing.matrix
            node.colorTransform = existing.colorTransform
            node.name = existing.name
            node.clipDepth = existing.clipDepth
        }
        apply(placement, to: node)
        if let replaced = parent.child(atDepth: placement.depth) {
            dispatchPlacementLifecycle(replaced, phase: .unloaded)
        }
        parent.addChild(node, atDepth: placement.depth)
        bringUp(node)
    }

    func apply(_ placement: SWFPlacement, to node: SWFDisplayObject) {
        if let matrix = placement.matrix {
            node.matrix = matrix
        }
        if let colorTransform = placement.colorTransform {
            node.colorTransform = colorTransform
        }
        if let ratio = placement.ratio {
            node.ratio = ratio
        }
        if let name = placement.name {
            node.name = name
            node.parent?.bindName(of: node)
        }
        if let clipDepth = placement.clipDepth {
            node.clipDepth = clipDepth
        }
        if let clipActions = placement.clipActions {
            node.clipActions = clipActions
            if !clipActions.allEvents.isDisjoint(with: [.keyDown, .keyUp, .keyPress]) {
                noteKeyClipHandler()
            }
        }
    }

    /// A newly placed instance: build its own frame 1, dispatch `initialize`,
    /// run the class its linkage name registered, then dispatch `construct` and
    /// `load` and run the frame's actions. The constructor sees a clip whose
    /// children already exist, which is what CLIK components expect, and the
    /// event order is the one the `ClipEventFlags` table implies.
    func bringUp(_ node: SWFDisplayObject) {
        let frames = frames(of: node)
        if node.isClip, !frames.isEmpty {
            apply(frame: frames[0], to: node)
            node.currentFrame = 0
        }
        dispatchPlacementLifecycle(node, phase: .initialize)
        constructRegisteredClass(for: node)
        dispatchPlacementLifecycle(node, phase: .constructed)
        if let first = frames.first {
            runActions(of: first, on: node)
        }
    }
}
