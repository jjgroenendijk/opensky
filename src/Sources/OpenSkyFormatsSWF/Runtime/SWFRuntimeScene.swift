// Draw commands from the mutable display tree: the live twin of
// `SWFScene.build(movie:)`, with the same commands and paint order, so the
// renderer does not know whether ActionScript runs. `textOverride` carries a
// field's runtime string.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// Regenerates the whole command stream from the live tree and clears the
    /// dirty flag.
    public func makeScene() -> SWFScene {
        var builder = SWFRuntimeSceneBuilder(runtime: self)
        builder.walk(node: root, parent: .root)
        clearDirty()
        return SWFScene(commands: builder.commands, skippedPlacements: builder.skipped)
    }

    /// The command stream, but only when the tree changed since the last call.
    /// The per-frame path uses this so an idle movie costs nothing.
    public func sceneIfChanged() -> SWFScene? {
        isDirty ? makeScene() : nil
    }
}

/// Depth-ordered walk with an active-clip stack per clip scope — the mutable
/// mirror of `SceneBuilder` in `SWFScene.swift`.
nonisolated private struct SWFRuntimeSceneBuilder {
    let runtime: SWFMovieRuntime
    var commands: [SWFSceneCommand] = []
    var skipped = 0

    /// A sprite's grid, bounds, and transform, for its direct shape children.
    struct GridContext {
        let splitter: SWFRect
        let bounds: SWFBoundsBox
        let transform: SWFTransform
    }

    /// Set by `emit` for the clip it walks next; `walk` takes it at entry.
    var pendingGrid: GridContext?

    mutating func walk(node: SWFDisplayObject, parent: SWFWalkState) {
        let grid = pendingGrid
        pendingGrid = nil
        var active: [(clipDepth: UInt16, masks: [SWFSceneItem])] = []
        for child in node.children {
            while let last = active.last, last.clipDepth < child.depth {
                commands.append(.endClip(masks: last.masks))
                active.removeLast()
            }
            guard child.isVisible else {
                continue
            }
            let transform = parent.transform
                .concatenating(SWFTransform(matrix: child.matrix))
            let color = parent.color.concatenating(child.colorTransform)
            if let clipDepth = child.clipDepth {
                let masks = maskItems(
                    node: child, transform: transform, color: color, spriteDepth: parent.spriteDepth
                )
                commands.append(.beginClip(masks: masks))
                active.append((clipDepth, masks))
            } else if case let .shape(id) = child.content {
                var item = SWFSceneItem(
                    content: .shape(id), transform: transform, colorTransform: color
                )
                item.scalingGrid = grid.flatMap {
                    SWFSceneScalingGrid.make(
                        splitter: $0.splitter, spriteBounds: $0.bounds,
                        spriteTransform: $0.transform, childMatrix: child.matrix
                    )
                }
                append(item, clipCount: parent.clipCount + active.count)
            } else {
                emit(
                    node: child,
                    state: SWFWalkState(
                        transform: transform, color: color,
                        clipCount: parent.clipCount + active.count, spriteDepth: parent.spriteDepth
                    )
                )
            }
        }
        for entry in active.reversed() {
            commands.append(.endClip(masks: entry.masks))
        }
    }

    private mutating func emit(node: SWFDisplayObject, state: SWFWalkState) {
        switch node.content {
        case .shape:
            // `walk` draws shapes itself, with the sprite's scaling grid.
            break
        case let .staticText(id):
            guard let text = runtime.movie.staticText(id) else {
                skipped += 1
                return
            }
            // Fold the text tag's own MATRIX so glyph layout stays in the
            // text's local record space, matching the static path.
            append(
                SWFSceneItem(
                    content: .staticText(id),
                    transform: state.transform.concatenating(SWFTransform(matrix: text.matrix)),
                    colorTransform: state.color
                ),
                clipCount: state.clipCount
            )
        case let .editText(id):
            append(
                SWFSceneItem(
                    content: .editText(id),
                    transform: state.transform,
                    colorTransform: state.color,
                    textOverride: runtime.text(of: node),
                    textFirstLine: runtime.windowsLines(node) ? runtime
                        .textScroll(of: node) - 1 : nil,
                    textBounds: node.textBounds
                ),
                clipCount: state.clipCount
            )
        case let .clip(id):
            guard state.spriteDepth < SWFScene.maximumSpriteDepth else {
                skipped += 1
                return
            }
            let splitter = id.flatMap { runtime.movie.sprite($0)?.scalingGrid }
            pendingGrid = splitter.map {
                GridContext(
                    splitter: $0, bounds: runtime.localBounds(of: node), transform: state.transform
                )
            }
            walk(node: node, parent: state.nested)
        }
    }

    private mutating func append(_ item: SWFSceneItem, clipCount: Int) {
        commands.append(.draw(item: item, clipCount: clipCount))
    }

    /// Stencil geometry for a clip layer: the shape itself, or every shape of a
    /// clip's subtree. Text masks stay unsupported, as in the static path.
    private mutating func maskItems(
        node: SWFDisplayObject,
        transform: SWFTransform,
        color: SWFColorTransform,
        spriteDepth: Int
    ) -> [SWFSceneItem] {
        switch node.content {
        case let .shape(id):
            return [SWFSceneItem(
                content: .shape(id), transform: transform, colorTransform: color
            )]
        case .clip:
            guard spriteDepth < SWFScene.maximumSpriteDepth else {
                skipped += 1
                return []
            }
            return node.children.flatMap { child in
                maskItems(
                    node: child,
                    transform: transform.concatenating(SWFTransform(matrix: child.matrix)),
                    color: color,
                    spriteDepth: spriteDepth + 1
                )
            }
        default:
            skipped += 1
            return []
        }
    }
}
