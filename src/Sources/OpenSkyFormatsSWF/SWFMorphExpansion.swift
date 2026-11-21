// Only timeline placements set a ratio, so each ratio a morph shape is shown at is
// known once the movie is decoded. Each one becomes a plain shape character with a
// free id, and its placements point at that id, so the rest of the engine draws
// shapes alone. See docs/formats/swf-shapes.md#morph-shapes.

import Foundation

nonisolated struct SWFMorphExpansion {
    private struct Instance: Hashable {
        let morph: UInt16
        let ratio: UInt16
    }

    private let morphs: [UInt16: SWFMorphShapeDefinition]
    private var taken: Set<UInt16>
    private var nextFree = UInt16.max
    private var instances: [Instance: UInt16] = [:]
    /// The shape characters made so far, by their new id.
    private(set) var shapes: [UInt16: SWFShapeDefinition] = [:]

    init(morphs: [UInt16: SWFMorphShapeDefinition], taken: Set<UInt16>) {
        self.morphs = morphs
        self.taken = taken.union(morphs.keys)
    }

    /// The movie's characters with every sprite's placements rewritten and the new
    /// shapes added, plus the rewritten main timeline.
    static func expand(
        morphs: [UInt16: SWFMorphShapeDefinition],
        characters: [UInt16: SWFCharacter],
        timeline: SWFTimeline,
        reservedIds: Set<UInt16>
    ) -> (characters: [UInt16: SWFCharacter], timeline: SWFTimeline) {
        guard !morphs.isEmpty else { return (characters, timeline) }
        var expansion = SWFMorphExpansion(
            morphs: morphs, taken: reservedIds.union(characters.keys)
        )
        var result = characters
        for (id, character) in characters {
            guard case let .sprite(sprite) = character else { continue }
            var rewritten = SWFSprite(
                characterId: sprite.characterId,
                frameCount: sprite.frameCount,
                timeline: expansion.rewrite(sprite.timeline)
            )
            rewritten.scalingGrid = sprite.scalingGrid
            result[id] = .sprite(rewritten)
        }
        let main = expansion.rewrite(timeline)
        for (id, shape) in expansion.shapes {
            result[id] = .shape(shape)
        }
        return (result, main)
    }

    /// Follows which character holds each depth, in tag order, and gives each
    /// placement that sets a morph or its ratio the id of the matching shape.
    mutating func rewrite(_ timeline: SWFTimeline) -> SWFTimeline {
        var occupant: [UInt16: UInt16] = [:]
        var ratios: [UInt16: UInt16] = [:]
        let frames = timeline.frames.map { frame in
            let steps = frame.steps.map { step -> SWFTimelineStep in
                switch step {
                case let .remove(removal):
                    occupant[removal.depth] = nil
                    ratios[removal.depth] = nil
                    return step
                case var .place(placement):
                    let depth = placement.depth
                    if let id = placement.characterId {
                        if !placement.isMove || occupant[depth] != id {
                            ratios[depth] = nil
                        }
                        occupant[depth] = id
                    } else if !placement.isMove {
                        return step
                    }
                    guard
                        let morph = occupant[depth], morphs[morph] != nil,
                        placement.characterId != nil || placement.ratio != nil
                    else { return step }
                    let ratio = placement.ratio ?? ratios[depth] ?? 0
                    ratios[depth] = ratio
                    placement.characterId = shapeId(morph: morph, ratio: ratio) ?? placement
                        .characterId
                    return .place(placement)
                }
            }
            return SWFTimelineFrame(steps: steps, actions: frame.actions, label: frame.label)
        }
        let frame1 = timeline.frame1.map { placed in
            guard morphs[placed.characterId] != nil else { return placed }
            var placed = placed
            placed.characterId = shapeId(morph: placed.characterId, ratio: placed.ratio ?? 0)
                ?? placed.characterId
            return placed
        }
        return SWFTimeline(frames: frames, frame1: frame1, tally: timeline.tally)
    }

    /// The id of the morph's shape at `ratio`, made on first use. Nil once every
    /// id is in use, which leaves the placement on the morph id, so it draws nothing.
    private mutating func shapeId(morph: UInt16, ratio: UInt16) -> UInt16? {
        let instance = Instance(morph: morph, ratio: ratio)
        if let id = instances[instance] {
            return id
        }
        guard let definition = morphs[morph], let id = freeId() else { return nil }
        instances[instance] = id
        shapes[id] = definition.shape(atRatio: ratio, characterId: id)
        return id
    }

    private mutating func freeId() -> UInt16? {
        while taken.contains(nextFree) {
            guard nextFree > 1 else { return nil }
            nextFree -= 1
        }
        taken.insert(nextFree)
        return nextFree
    }
}
