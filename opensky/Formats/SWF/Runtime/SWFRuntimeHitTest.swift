// Pointer hit testing against the runtime display tree (milestone 8.3.2 phase
// 3). Answers "which display object is under this stage point", which is what
// rollover, rollout, press, and release routing all start from.
//
// The walk is the paint order reversed, because the object drawn last is the
// object on top. It respects three things the scene generator also respects:
// `_visible` (an invisible subtree draws nothing and therefore catches
// nothing), the accumulated matrix chain (the point is carried down into each
// node's local space rather than the node's box being carried up), and clip
// layers (a node masked by a `ClipDepth` layer is only hit where the mask is).
//
// Resolution is bounding-box, not shape-level: a node is hit when the point
// falls inside its character bounds. That matches `MovieClip.hitTest`, which is
// bounding-box in Flash as well, and it matches what vanilla CLIK asks for —
// every mouse-enabled control in the library is a rectangular button or list
// row. A rotated or non-rectangular control therefore has a slightly generous
// hit area. Shape-level testing would need the tessellated outline and is not
// implemented.

import Foundation
import simd

/// What a hit test found: the topmost mouse-enabled node under the pointer, and
/// the topmost node of any kind, which is what a diagnostic readout wants.
nonisolated struct SWFHitResult {
    /// The node that should receive `onPress`, or nil when the pointer is over
    /// nothing interactive.
    let target: SWFDisplayObject?
    /// The topmost drawable node under the pointer, interactive or not.
    let topmost: SWFDisplayObject?
}

nonisolated extension SWFMovieRuntime {
    /// The handler members that make a clip mouse-enabled. Flash routes a mouse
    /// event to a clip only when the clip can handle one; CLIK's `Button`
    /// assigns `onPress`, `onRelease`, `onRollOver`, and `onRollOut` in
    /// `configUI`, so the presence of any of them is the test.
    static let mouseHandlerNames = [
        "onPress", "onRelease", "onReleaseOutside", "onRollOver", "onRollOut",
        "onDragOver", "onDragOut", "onMouseDown", "onMouseUp"
    ]

    /// Hit tests the whole tree at a point in stage twips.
    func hitTest(stageTwips point: SIMD2<Float>) -> SWFHitResult {
        var search = SWFHitSearch(runtime: self, point: point)
        search.walk(node: root, transform: .identity, depth: 0)
        return SWFHitResult(target: search.target, topmost: search.topmost)
    }

    /// True when the node itself can consume a mouse event, either through a
    /// handler member or a CLIPACTIONS mouse handler.
    func isMouseEnabled(_ node: SWFDisplayObject) -> Bool {
        guard node.isClip else {
            return false
        }
        if let events = node.clipActions?.allEvents, !events.isDisjoint(with: .mouseEvents) {
            return true
        }
        return Self.mouseHandlerNames.contains { node.object.lookup($0) != nil }
    }

    /// True when the point falls inside the node's own character bounds,
    /// expressed in the node's local space.
    func containsLocally(_ node: SWFDisplayObject, localPoint: SIMD2<Float>) -> Bool {
        localBounds(of: node).contains(localPoint)
    }
}

nonisolated extension SWFClipEventFlags {
    /// Every mouse-driven clip event, for deciding whether a node is a mouse
    /// target without naming each flag at the call site.
    static let mouseEvents: SWFClipEventFlags = [
        .mouseMove, .mouseDown, .mouseUp, .press, .release, .releaseOutside,
        .rollOver, .rollOut, .dragOver, .dragOut
    ]
}

/// Depth-first walk carrying the point down into each node's local space.
/// Children are visited in reverse paint order so the first mouse-enabled hit
/// is the topmost one.
nonisolated private struct SWFHitSearch {
    let runtime: SWFMovieRuntime
    /// The probe point, in stage twips.
    let point: SIMD2<Float>
    var target: SWFDisplayObject?
    var topmost: SWFDisplayObject?

    /// True once both answers are settled and the walk can stop early.
    private var isSettled: Bool {
        target != nil && topmost != nil
    }

    mutating func walk(node: SWFDisplayObject, transform: SWFTransform, depth: Int) {
        guard depth < SWFDisplayObject.maximumTreeDepth, !isSettled else {
            return
        }
        let masks = maskRanges(of: node, transform: transform)
        for child in node.children.reversed() where child.isVisible && child.clipDepth == nil {
            guard !isMasked(child, by: masks) else {
                continue
            }
            let childTransform = transform
                .concatenating(SWFTransform(matrix: child.matrix))
            visit(child, transform: childTransform, depth: depth)
            if isSettled {
                return
            }
        }
    }

    private mutating func visit(
        _ child: SWFDisplayObject,
        transform: SWFTransform,
        depth: Int
    ) {
        if child.isClip {
            walk(node: child, transform: transform, depth: depth + 1)
            if isSettled {
                return
            }
        }
        guard
            let inverse = transform.inverted,
            runtime.containsLocally(child, localPoint: inverse.apply(point))
        else {
            return
        }
        if topmost == nil {
            topmost = child
        }
        if target == nil, runtime.isMouseEnabled(child) {
            target = child
        }
    }

    /// The clip layers active in a node's child list, each as the depth range it
    /// masks plus the stage-space box the mask covers. A `ClipDepth` layer masks
    /// depths `(depth, clipDepth]`, which is the same rule the scene generator
    /// uses to emit `beginClip` / `endClip`.
    private func maskRanges(
        of node: SWFDisplayObject,
        transform: SWFTransform
    ) -> [(range: ClosedRange<UInt16>, box: SWFBoundsBox)] {
        node.children.compactMap { child in
            guard let clipDepth = child.clipDepth, clipDepth >= child.depth else {
                return nil
            }
            let box = runtime.localBounds(of: child).transformed(
                by: transform.concatenating(SWFTransform(matrix: child.matrix))
            )
            return (child.depth ... clipDepth, box)
        }
    }

    private func isMasked(
        _ child: SWFDisplayObject,
        by masks: [(range: ClosedRange<UInt16>, box: SWFBoundsBox)]
    ) -> Bool {
        masks.contains { mask in
            mask.range.contains(child.depth) && !mask.box.contains(point)
        }
    }
}
