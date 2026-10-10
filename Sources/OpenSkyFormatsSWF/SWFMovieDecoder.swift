// One pass over a movie's tag stream: definition tags feed the character
// dictionary, control tags feed the timeline, and DoInitAction blocks are
// collected by sprite id.
// Reference: Adobe SWF File Format Specification v19, chapters 3, 5 and 13.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct SWFMovieDecoder: Sendable {
    public let version: UInt8
    public let jpegTables: Data?
    public var characters: [UInt16: SWFCharacter] = [:]
    public var importedNames: [UInt16: String] = [:]
    /// Every ImportAssets/ImportAssets2 tag with its source movie URL, in tag
    /// order. `importedNames` loses the URL, and resolving a non-font import
    /// needs it.
    public var imports: [SWFImportedAssets] = []
    public var exportedNames: [String: UInt16] = [:]
    public var initActions: [SWFDoInitAction] = []
    public var timeline: SWFTimelineDecoder
    /// Display-list and action counters summed over every sprite.
    public var spriteTally = SWFMovieTally()
    /// Definition tags this decoder skipped because they failed to parse.
    public var malformedTags = 0

    public init(version: UInt8, jpegTables: Data?) {
        self.version = version
        self.jpegTables = jpegTables
        timeline = SWFTimelineDecoder(version: version)
    }

    public mutating func run(tags: [SWFTag]) throws {
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
            if let initAction = parsed({ try SWFActionParser.parseDoInitAction(tag: tag) }) {
                initActions.append(initAction)
            }
        } else if SWFImportedAssets.tagCodes.contains(tag.code) {
            let imported = try SWFImportedAssets.parse(tag: tag)
            imports.append(imported)
            for asset in imported.assets {
                importedNames[asset.characterId] = asset.name
            }
        } else if tag.code == SWFExportedAssets.tagCode {
            // Linkage names: what Object.registerClass and attachMovie address.
            // A malformed table costs the linkage, never the movie — the
            // affected classes simply never instantiate.
            for asset in parsed({ try SWFExportedAssets.parse(tag: tag) })?.assets ?? [] {
                exportedNames[asset.name] = asset.characterId
            }
        }
    }

    private mutating func parsed<Value>(_ parse: () throws -> Value) -> Value? {
        do {
            return try parse()
        } catch {
            malformedTags += 1
            return nil
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
