// Single pass over a movie's tag stream, split out of `SWFMovie.swift` to stay
// under the file-size limit: definition tags feed the character dictionary,
// control tags and DoAction blocks feed the timeline, and DoInitAction (59)
// blocks are collected by sprite id.
//
// Reference: Adobe SWF File Format Specification, version 19 — chapter 3 "The
// display list" (pp. 33-51), chapter 5 "Actions" DoInitAction (p. 108), and
// chapter 13 "Sprites and movie clips" DefineSprite (p. 201).

import Foundation

nonisolated struct SWFMovieDecoder {
    let version: UInt8
    let jpegTables: Data?
    var characters: [UInt16: SWFCharacter] = [:]
    var importedNames: [UInt16: String] = [:]
    var initActions: [SWFDoInitAction] = []
    var timeline: SWFTimelineDecoder
    /// Display-list and action counters summed over every sprite.
    var spriteTally = SWFMovieTally()

    init(version: UInt8, jpegTables: Data?) {
        self.version = version
        self.jpegTables = jpegTables
        timeline = SWFTimelineDecoder(version: version)
    }

    mutating func run(tags: [SWFTag]) throws {
        for tag in tags {
            try decodeDefinition(tag)
            timeline.accept(tag)
        }
    }

    private mutating func decodeDefinition(_ tag: SWFTag) throws {
        if SWFShapeDefinition.tagCodes.contains(tag.code) {
            let shape = try SWFShapeDefinition.parse(tag: tag)
            characters[shape.characterId] = .shape(shape)
        } else if SWFBitmapDecoder.tagCodes.contains(tag.code) {
            let bitmap = try SWFBitmapDecoder.decode(tag: tag, jpegTables: jpegTables)
            characters[bitmap.characterId] = .bitmap(bitmap)
        } else if SWFFontDefinition.tagCodes.contains(tag.code) {
            let font = try SWFFontParser.parse(tag: tag)
            characters[font.fontID] = .font(font)
        } else if SWFTextDefinition.tagCodes.contains(tag.code) {
            let text = try SWFTextDefinition.parse(tag: tag)
            characters[text.characterId] = .staticText(text)
        } else if tag.code == SWFEditText.tagCode {
            let text = try SWFEditText.parse(tag: tag)
            characters[text.characterId] = .editText(text)
        } else if tag.code == SWFDisplayListParser.defineSpriteCode {
            let sprite = try decodeSprite(tag)
            characters[sprite.characterId] = .sprite(sprite)
        } else if tag.code == SWFActionParser.doInitActionCode {
            // A malformed DoInitAction loses its actions, never the movie.
            if let initAction = try? SWFActionParser.parseDoInitAction(tag: tag) {
                initActions.append(initAction)
            }
        } else if SWFImportedAssets.tagCodes.contains(tag.code) {
            for asset in try SWFImportedAssets.parse(tag: tag).assets {
                importedNames[asset.characterId] = asset.name
            }
        }
    }

    /// DefineSprite (39): SpriteID UI16, FrameCount UI16, then a nested
    /// control-tag stream (End-terminated) forming the sprite's own timeline.
    /// The whole stream is decoded now, not just up to the first ShowFrame, so
    /// a sprite's later frames and its DoAction blocks survive.
    private mutating func decodeSprite(_ tag: SWFTag) throws -> SWFSprite {
        var reader = BinaryReader(tag.body)
        let spriteId = try reader.readUInt16()
        let spriteFrameCount = try reader.readUInt16()
        let nested = try SWFFile.parseTags(&reader)
        var decoder = SWFTimelineDecoder(version: version)
        for nestedTag in nested {
            decoder.accept(nestedTag)
        }
        let spriteTimeline = decoder.finish()
        spriteTally.add(spriteTimeline.tally)
        spriteTally.add(spriteTimeline.actionTally)
        spriteTally.sprites += 1
        return SWFSprite(
            characterId: spriteId,
            frameCount: spriteFrameCount,
            timeline: spriteTimeline
        )
    }
}
