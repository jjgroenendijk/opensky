// Flattens a movie's frame-1 display list into an ordered draw-command
// stream: sprites expand recursively (their own frame 1), matrices and color
// transforms concatenate down the chain, and clip layers (PlaceObject
// clipDepth) become begin/end mask commands with a running active-clip count.
//
// Clip semantics (SWF spec v19, PlaceObject2 ClipDepth, p. 34): a placement
// with a clip depth renders no color itself and masks every placement at
// depths (depth, clipDepth]. Clip ranges may interleave, so the renderer uses
// a counting stencil: each active mask increments the pixels it covers, and a
// draw passes where the stencil equals the number of masks active at its
// depth — exactly the intersection of every active clip.

import Foundation

/// One drawable resolved from the display list: a character reference plus
/// the accumulated transform (character-local twips -> movie twips) and color
/// transform.
nonisolated struct SWFSceneItem: Equatable {
    enum Content: Equatable {
        case shape(UInt16)
        case staticText(UInt16)
        case editText(UInt16)
    }

    let content: Content
    let transform: SWFTransform
    let colorTransform: SWFColorTransform
}

/// Ordered render commands for one frame. Masks carry the geometry items the
/// stencil pass draws (a clip layer that is a sprite contributes every shape
/// of its frame 1); `endClip` repeats the same items so the renderer can
/// decrement exactly what was incremented.
nonisolated enum SWFSceneCommand: Equatable {
    case beginClip(masks: [SWFSceneItem])
    case endClip(masks: [SWFSceneItem])
    case draw(item: SWFSceneItem, clipCount: Int)
}

/// The flattened frame: commands in paint order plus skip accounting.
nonisolated struct SWFScene: Equatable {
    let commands: [SWFSceneCommand]
    /// Placements referencing characters that cannot draw (missing ids,
    /// fonts/bitmaps placed directly, text used as a clip mask).
    let skippedPlacements: Int

    /// Sprite recursion is bounded defensively; vanilla nesting is shallow.
    static let maximumSpriteDepth = 16

    static func build(movie: SWFMovie) -> SWFScene {
        var builder = SceneBuilder(movie: movie)
        builder.walk(
            placements: movie.frame1,
            parentTransform: .identity,
            parentColor: .identity,
            clipCount: 0,
            spriteDepth: 0
        )
        return SWFScene(
            commands: builder.commands,
            skippedPlacements: builder.skipped
        )
    }
}

/// Depth-ordered walk with an active-clip stack per timeline scope.
private struct SceneBuilder {
    let movie: SWFMovie
    var commands: [SWFSceneCommand] = []
    var skipped = 0

    /// Walks one timeline's placements (already depth-ascending). `clipCount`
    /// is the number of masks active in enclosing scopes; local clips add to
    /// it for nested draws.
    mutating func walk(
        placements: [SWFPlacedObject],
        parentTransform: SWFTransform,
        parentColor: SWFColorTransform,
        clipCount: Int,
        spriteDepth: Int
    ) {
        // Local clip stack: (clipDepth, mask items), expired in depth order.
        var active: [(clipDepth: UInt16, masks: [SWFSceneItem])] = []
        for placement in placements {
            while let last = active.last, last.clipDepth < placement.depth {
                commands.append(.endClip(masks: last.masks))
                active.removeLast()
            }
            let transform = parentTransform
                .concatenating(SWFTransform(matrix: placement.matrix))
            let color = parentColor.concatenating(placement.colorTransform)
            if placement.clipDepth != nil {
                let masks = maskItems(
                    characterId: placement.characterId,
                    transform: transform,
                    color: color,
                    spriteDepth: spriteDepth
                )
                commands.append(.beginClip(masks: masks))
                active.append((placement.clipDepth ?? placement.depth, masks))
            } else {
                emit(
                    placement: placement,
                    transform: transform,
                    color: color,
                    clipCount: clipCount + active.count,
                    spriteDepth: spriteDepth
                )
            }
        }
        for entry in active.reversed() {
            commands.append(.endClip(masks: entry.masks))
        }
    }

    private mutating func emit(
        placement: SWFPlacedObject,
        transform: SWFTransform,
        color: SWFColorTransform,
        clipCount: Int,
        spriteDepth: Int
    ) {
        switch movie.characters[placement.characterId] {
        case let .shape(shape):
            let item = SWFSceneItem(
                content: .shape(shape.characterId), transform: transform, colorTransform: color
            )
            commands.append(.draw(item: item, clipCount: clipCount))
        case let .staticText(text):
            // Fold the text tag's own placement MATRIX here so glyph layout
            // stays in the text's local record space.
            let item = SWFSceneItem(
                content: .staticText(text.characterId),
                transform: transform.concatenating(SWFTransform(matrix: text.matrix)),
                colorTransform: color
            )
            commands.append(.draw(item: item, clipCount: clipCount))
        case let .editText(text):
            let item = SWFSceneItem(
                content: .editText(text.characterId), transform: transform, colorTransform: color
            )
            commands.append(.draw(item: item, clipCount: clipCount))
        case let .sprite(sprite):
            guard spriteDepth < SWFScene.maximumSpriteDepth else {
                skipped += 1
                return
            }
            walk(
                placements: sprite.frame1,
                parentTransform: transform,
                parentColor: color,
                clipCount: clipCount,
                spriteDepth: spriteDepth + 1
            )
        default:
            // Fonts and bitmaps are referenced, never placed; a missing id is
            // a dangling placement.
            skipped += 1
        }
    }

    /// The stencil geometry a clip layer contributes: the shape itself, or a
    /// sprite's frame-1 shapes recursively. Text masks are unsupported at
    /// this stage (skipped + counted); vanilla clip layers are shape-based.
    private mutating func maskItems(
        characterId: UInt16,
        transform: SWFTransform,
        color: SWFColorTransform,
        spriteDepth: Int
    ) -> [SWFSceneItem] {
        switch movie.characters[characterId] {
        case let .shape(shape):
            return [SWFSceneItem(
                content: .shape(shape.characterId), transform: transform, colorTransform: color
            )]
        case let .sprite(sprite):
            guard spriteDepth < SWFScene.maximumSpriteDepth else {
                skipped += 1
                return []
            }
            return sprite.frame1.flatMap { placement in
                maskItems(
                    characterId: placement.characterId,
                    transform: transform
                        .concatenating(SWFTransform(matrix: placement.matrix)),
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
