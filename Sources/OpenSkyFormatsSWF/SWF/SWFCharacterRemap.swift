// Shifts every character ID of an imported movie by one offset, so its IDs
// cannot collide with the importer's. A missed ID field gives a wrong movie,
// so every ID-bearing field is listed in the code below.
// See docs/formats/swf-display-list.md.

import Foundation

/// Shifts every character id of one decoded source movie by a constant offset.
/// The shift saturates at `UInt16.max` instead of wrapping: an id that would
/// leave the 16-bit space becomes a reference to nothing, which the display
/// list already tolerates, and is counted in `saturatedReferences`.
nonisolated public struct SWFCharacterRemap: Sendable {
    public let offset: Int
    /// References that could not be shifted inside `UInt16` and were saturated.
    public private(set) var saturatedReferences = 0

    public mutating func id(_ value: UInt16) -> UInt16 {
        let shifted = Int(value) + offset
        guard shifted <= Int(UInt16.max) else {
            saturatedReferences += 1
            return UInt16.max
        }
        return UInt16(shifted)
    }

    public mutating func id(optional value: UInt16?) -> UInt16? {
        guard let value else {
            return nil
        }
        return id(value)
    }

    // MARK: - Dictionary

    /// The whole character dictionary, keys and internal references alike. A
    /// key that saturates would land on top of another character, so it is
    /// dropped rather than merged wrong; the count still records the loss.
    public mutating func characters(_ source: [UInt16: SWFCharacter]) -> [UInt16: SWFCharacter] {
        var result: [UInt16: SWFCharacter] = [:]
        result.reserveCapacity(source.count)
        for key in source.keys.sorted() {
            guard let value = source[key] else { continue }
            let shifted = Int(key) + offset
            guard shifted <= Int(UInt16.max) else {
                saturatedReferences += 1
                continue
            }
            result[UInt16(shifted)] = character(value)
        }
        return result
    }

    public mutating func character(_ source: SWFCharacter) -> SWFCharacter {
        switch source {
        case let .shape(shape): .shape(self.shape(shape))
        case let .bitmap(bitmap): .bitmap(self.bitmap(bitmap))
        case let .font(font): .font(self.font(font))
        case let .staticText(text): .staticText(staticText(text))
        case let .editText(text): .editText(editText(text))
        case let .sprite(sprite): .sprite(self.sprite(sprite))
        }
    }

    // MARK: - Definitions

    public mutating func shape(_ source: SWFShapeDefinition) -> SWFShapeDefinition {
        SWFShapeDefinition(
            characterId: id(source.characterId),
            bounds: source.bounds,
            edgeBounds: source.edgeBounds,
            usesFillWindingRule: source.usesFillWindingRule,
            fillStyles: source.fillStyles.map { fillStyle($0) },
            lineStyles: source.lineStyles.map { lineStyle($0) },
            segments: source.segments
        )
    }

    public mutating func bitmap(_ source: SWFBitmap) -> SWFBitmap {
        SWFBitmap(
            characterId: id(source.characterId),
            width: source.width,
            height: source.height,
            pixels: source.pixels,
            premultipliedAlpha: source.premultipliedAlpha,
            sourceFormat: source.sourceFormat,
            jpegDeblockParam: source.jpegDeblockParam
        )
    }

    public mutating func font(_ source: SWFFontDefinition) -> SWFFontDefinition {
        SWFFontDefinition(
            fontID: id(source.fontID),
            isHighResolution: source.isHighResolution,
            flags: source.flags,
            languageCode: source.languageCode,
            name: source.name,
            glyphs: source.glyphs,
            layout: source.layout
        )
    }

    public mutating func staticText(_ source: SWFTextDefinition) -> SWFTextDefinition {
        SWFTextDefinition(
            characterId: id(source.characterId),
            bounds: source.bounds,
            matrix: source.matrix,
            records: source.records.map { textRecord($0) }
        )
    }

    public mutating func editText(_ source: SWFEditText) -> SWFEditText {
        SWFEditText(
            characterId: id(source.characterId),
            bounds: source.bounds,
            flags: source.flags,
            fontID: id(optional: source.fontID),
            fontClass: source.fontClass,
            fontHeight: source.fontHeight,
            color: source.color,
            maxLength: source.maxLength,
            layout: source.layout,
            variableName: source.variableName,
            initialText: source.initialText
        )
    }

    public mutating func sprite(_ source: SWFSprite) -> SWFSprite {
        SWFSprite(
            characterId: id(source.characterId),
            frameCount: source.frameCount,
            timeline: timeline(source.timeline)
        )
    }

    // MARK: - Timelines

    public mutating func timeline(_ source: SWFTimeline) -> SWFTimeline {
        SWFTimeline(
            frames: source.frames.map { frame($0) },
            frame1: source.frame1.map { placedObject($0) },
            tally: source.tally
        )
    }

    public mutating func initActions(_ source: [SWFDoInitAction]) -> [SWFDoInitAction] {
        source.map { SWFDoInitAction(spriteId: id($0.spriteId), actions: $0.actions) }
    }

    // MARK: - Name tables

    public mutating func exportedNames(_ source: [String: UInt16]) -> [String: UInt16] {
        var result: [String: UInt16] = [:]
        result.reserveCapacity(source.count)
        for name in source.keys.sorted() {
            guard let value = source[name] else { continue }
            result[name] = id(value)
        }
        return result
    }

    public mutating func importedNames(_ source: [UInt16: String]) -> [UInt16: String] {
        var result: [UInt16: String] = [:]
        result.reserveCapacity(source.count)
        for key in source.keys.sorted() {
            guard let value = source[key] else { continue }
            result[id(key)] = value
        }
        return result
    }

    // MARK: - Private

    private mutating func textRecord(_ source: SWFTextRecord) -> SWFTextRecord {
        SWFTextRecord(
            fontID: id(optional: source.fontID),
            textHeight: source.textHeight,
            color: source.color,
            xOffset: source.xOffset,
            yOffset: source.yOffset,
            glyphs: source.glyphs
        )
    }

    private mutating func fillStyle(_ source: SWFFillStyle) -> SWFFillStyle {
        guard case let .bitmap(characterId, matrix, tiled, smoothed) = source else {
            return source
        }
        return .bitmap(
            characterId: id(characterId), matrix: matrix, tiled: tiled, smoothed: smoothed
        )
    }

    private mutating func lineStyle(_ source: SWFLineStyle) -> SWFLineStyle {
        guard let fill = source.fill else {
            return source
        }
        var result = source
        result.fill = fillStyle(fill)
        return result
    }

    private mutating func frame(_ source: SWFTimelineFrame) -> SWFTimelineFrame {
        SWFTimelineFrame(
            steps: source.steps.map { step($0) },
            actions: source.actions,
            label: source.label
        )
    }

    private mutating func step(_ source: SWFTimelineStep) -> SWFTimelineStep {
        switch source {
        case let .place(placement): .place(self.placement(placement))
        case let .remove(removal): .remove(self.removal(removal))
        }
    }

    private mutating func placement(_ source: SWFPlacement) -> SWFPlacement {
        var result = source
        result.characterId = id(optional: source.characterId)
        return result
    }

    private mutating func removal(_ source: SWFRemoval) -> SWFRemoval {
        SWFRemoval(depth: source.depth, characterId: id(optional: source.characterId))
    }

    private mutating func placedObject(_ source: SWFPlacedObject) -> SWFPlacedObject {
        var result = source
        result.characterId = id(source.characterId)
        return result
    }
}
