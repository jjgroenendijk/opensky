// Movie model for the display-list renderer (milestone 8.2.4): the character
// dictionary (shapes, bitmaps, fonts, texts, edit texts, sprites) plus the
// frame-1 display list — every place/modify/remove tag applied up to the
// first ShowFrame. Sprite characters (DefineSprite, 39) decode their own
// nested tag stream and keep their own frame-1 list; rendering nested sprites
// beyond frame 1 (timeline animation) is 8.3.x work.
//
// Reference: Adobe SWF File Format Specification, version 19 — chapter 3
// "The display list" (pp. 31-39) and DefineSprite (chapter 13, p. 233).

import Foundation

/// One entry of the character dictionary, keyed by character id.
nonisolated enum SWFCharacter {
    case shape(SWFShapeDefinition)
    case bitmap(SWFBitmap)
    case font(SWFFontDefinition)
    case staticText(SWFTextDefinition)
    case editText(SWFEditText)
    case sprite(SWFSprite)
}

/// A DefineSprite character: its declared frame count plus its frame-1
/// display list (nested placements resolved by depth like the main timeline).
nonisolated struct SWFSprite {
    let characterId: UInt16
    let frameCount: UInt16
    let frame1: [SWFPlacedObject]
}

/// One resolved display-list slot after executing the placement tags: the
/// character occupying a depth with its accumulated state.
nonisolated struct SWFPlacedObject: Equatable {
    var depth: UInt16
    var characterId: UInt16
    var matrix = SWFMatrix.identity
    var colorTransform = SWFColorTransform.identity
    var ratio: UInt16?
    var name: String?
    var clipDepth: UInt16?
}

/// Feature counters accumulated while decoding a movie's display list —
/// including the recorded-but-ignored PlaceObject3 extras, so the sweep can
/// report exactly what the renderer defers.
nonisolated struct SWFMovieTally: Equatable {
    var placeObject = 0
    var placeObject2 = 0
    var placeObject3 = 0
    var moves = 0
    var removals = 0
    var showFrames = 0
    var sprites = 0
    var clipLayers = 0
    var filters = 0
    var blendModes = 0
    var clipActions = 0
    /// Placements naming a character id absent from the dictionary, or a
    /// modify targeting an empty depth — skipped, never fatal.
    var danglingPlacements = 0

    mutating func add(_ other: SWFMovieTally) {
        placeObject += other.placeObject
        placeObject2 += other.placeObject2
        placeObject3 += other.placeObject3
        moves += other.moves
        removals += other.removals
        showFrames += other.showFrames
        sprites += other.sprites
        clipLayers += other.clipLayers
        filters += other.filters
        blendModes += other.blendModes
        clipActions += other.clipActions
        danglingPlacements += other.danglingPlacements
    }
}

/// Applies place/modify/remove semantics to a depth-keyed display list
/// (spec PlaceObject2, p. 34): PlaceFlagMove off + character id -> place a
/// new character; PlaceFlagMove on without a character id -> modify the
/// object at the depth; both -> replace the character at the depth. The spec
/// leaves the unspecified fields of a replace undefined; observed Flash/GFx
/// behavior keeps the previous state, which is what this does.
nonisolated struct SWFDisplayListBuilder {
    private var byDepth: [UInt16: SWFPlacedObject] = [:]
    private(set) var tally = SWFMovieTally()

    /// The current list, depth-ascending (the paint order).
    var placements: [SWFPlacedObject] {
        byDepth.values.sorted { $0.depth < $1.depth }
    }

    mutating func apply(_ placement: SWFPlacement) {
        tally.filters += placement.filterCount
        if placement.blendMode != nil {
            tally.blendModes += 1
        }
        if placement.hasClipActions {
            tally.clipActions += 1
        }
        if placement.clipDepth != nil {
            tally.clipLayers += 1
        }
        if placement.isMove {
            tally.moves += 1
        }
        guard var object = targetObject(for: placement) else {
            tally.danglingPlacements += 1
            return
        }
        if let matrix = placement.matrix {
            object.matrix = matrix
        }
        if let colorTransform = placement.colorTransform {
            object.colorTransform = colorTransform
        }
        if let ratio = placement.ratio {
            object.ratio = ratio
        }
        if let name = placement.name {
            object.name = name
        }
        if let clipDepth = placement.clipDepth {
            object.clipDepth = clipDepth
        }
        byDepth[placement.depth] = object
    }

    mutating func remove(_ removal: SWFRemoval) {
        tally.removals += 1
        byDepth.removeValue(forKey: removal.depth)
    }

    /// The object the placement's fields apply to: the existing slot for a
    /// modify, the existing state with a swapped character id for a replace,
    /// or a fresh object for a plain place. nil when a modify targets an
    /// empty depth.
    private func targetObject(for placement: SWFPlacement) -> SWFPlacedObject? {
        let existing = byDepth[placement.depth]
        guard let characterId = placement.characterId else {
            return placement.isMove ? existing : nil
        }
        if placement.isMove, var replaced = existing {
            replaced.characterId = characterId
            return replaced
        }
        return SWFPlacedObject(depth: placement.depth, characterId: characterId)
    }
}

/// A decoded movie ready for scene flattening: header framing, dictionary,
/// background color, and the frame-1 display list.
nonisolated struct SWFMovie {
    let frameSize: SWFRect
    let frameCount: UInt16
    /// SetBackgroundColor (9); nil when the movie never sets one.
    let backgroundColor: SWFColor?
    let characters: [UInt16: SWFCharacter]
    /// Main-timeline display list at the first ShowFrame, depth-ascending.
    let frame1: [SWFPlacedObject]
    /// Characters this movie imports by name (ImportAssets/ImportAssets2):
    /// character id -> export name in the source movie. Vanilla movies import
    /// their fonts this way, so an edit text's FontID often lands here rather
    /// than in `characters`.
    let importedNames: [UInt16: String]
    let tally: SWFMovieTally

    init(file: SWFFile) throws {
        frameSize = file.frameSize
        frameCount = file.frameCount
        let jpegTables = file.tags
            .first { $0.code == SWFBitmapDecoder.jpegTablesTagCode }?.body
        var decoder = MovieDecoder(jpegTables: jpegTables)
        try decoder.run(tags: file.tags)
        backgroundColor = decoder.backgroundColor
        characters = decoder.characters
        importedNames = decoder.importedNames
        frame1 = decoder.timeline.placements
        var total = decoder.timeline.tally
        total.add(decoder.spriteTally)
        tally = total
    }

    func shape(_ id: UInt16) -> SWFShapeDefinition? {
        if case let .shape(shape) = characters[id] {
            return shape
        }
        return nil
    }

    func bitmap(_ id: UInt16) -> SWFBitmap? {
        if case let .bitmap(bitmap) = characters[id] {
            return bitmap
        }
        return nil
    }

    func font(_ id: UInt16) -> SWFFontDefinition? {
        if case let .font(font) = characters[id] {
            return font
        }
        return nil
    }

    func editText(_ id: UInt16) -> SWFEditText? {
        if case let .editText(text) = characters[id] {
            return text
        }
        return nil
    }

    func staticText(_ id: UInt16) -> SWFTextDefinition? {
        if case let .staticText(text) = characters[id] {
            return text
        }
        return nil
    }

    func sprite(_ id: UInt16) -> SWFSprite? {
        if case let .sprite(sprite) = characters[id] {
            return sprite
        }
        return nil
    }
}

/// Walks a tag stream once: define tags feed the dictionary, display-list
/// tags execute on the timeline until its first ShowFrame.
private struct MovieDecoder {
    let jpegTables: Data?
    var characters: [UInt16: SWFCharacter] = [:]
    var importedNames: [UInt16: String] = [:]
    var backgroundColor: SWFColor?
    var timeline = SWFDisplayListBuilder()
    var spriteTally = SWFMovieTally()
    private var timelineFrozen = false

    init(jpegTables: Data?) {
        self.jpegTables = jpegTables
    }

    mutating func run(tags: [SWFTag]) throws {
        for tag in tags {
            try decodeDefinition(tag)
            guard !timelineFrozen else { continue }
            if let background = Self.applyControl(tag, to: &timeline) {
                backgroundColor = background
            }
            if tag.code == SWFDisplayListParser.showFrameCode {
                // Frame 1 is complete; later define tags still enter the
                // dictionary, later frames are 8.3.x timeline work.
                timelineFrozen = true
            }
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
        } else if SWFImportedAssets.tagCodes.contains(tag.code) {
            for asset in try SWFImportedAssets.parse(tag: tag).assets {
                importedNames[asset.characterId] = asset.name
            }
        }
    }

    /// DefineSprite (39): SpriteID UI16, FrameCount UI16, then a nested
    /// control-tag stream (End-terminated) forming the sprite's own timeline.
    private mutating func decodeSprite(_ tag: SWFTag) throws -> SWFSprite {
        var reader = BinaryReader(tag.body)
        let spriteId = try reader.readUInt16()
        let spriteFrameCount = try reader.readUInt16()
        let nested = try SWFFile.parseTags(&reader)
        var builder = SWFDisplayListBuilder()
        for nestedTag in nested {
            _ = Self.applyControl(nestedTag, to: &builder)
            if nestedTag.code == SWFDisplayListParser.showFrameCode {
                break
            }
        }
        spriteTally.add(builder.tally)
        spriteTally.sprites += 1
        return SWFSprite(
            characterId: spriteId,
            frameCount: spriteFrameCount,
            frame1: builder.placements
        )
    }

    /// Executes one display-list control tag against a builder, returning a
    /// decoded background color when the tag is SetBackgroundColor. A
    /// malformed control tag is skipped (counted as dangling) rather than
    /// failing the movie — placements are per-tag independent. Static so the
    /// caller can pass its own stored builder inout without overlapping
    /// access to self.
    private static func applyControl(
        _ tag: SWFTag,
        to builder: inout SWFDisplayListBuilder
    ) -> SWFColor? {
        switch tag.code {
        case SWFDisplayListParser.placeObjectCode,
             SWFDisplayListParser.placeObject2Code,
             SWFDisplayListParser.placeObject3Code:
            recordPlaceTally(tag.code, in: &builder)
            if let placement = try? SWFDisplayListParser.parsePlacement(tag: tag) {
                builder.apply(placement)
            } else {
                builder.noteDanglingPlacement()
            }
        case SWFDisplayListParser.removeObjectCode,
             SWFDisplayListParser.removeObject2Code:
            if let removal = try? SWFDisplayListParser.parseRemoval(tag: tag) {
                builder.remove(removal)
            }
        case SWFDisplayListParser.setBackgroundColorCode:
            return try? SWFDisplayListParser.parseBackgroundColor(tag: tag)
        case SWFDisplayListParser.showFrameCode:
            builder.noteShowFrame()
        default:
            break
        }
        return nil
    }

    private static func recordPlaceTally(_ code: UInt16, in builder: inout SWFDisplayListBuilder) {
        switch code {
        case SWFDisplayListParser.placeObjectCode: builder.notePlaceObject(version: 1)
        case SWFDisplayListParser.placeObject2Code: builder.notePlaceObject(version: 2)
        default: builder.notePlaceObject(version: 3)
        }
    }
}

extension SWFDisplayListBuilder {
    /// Tally-only notes recorded by the movie decoder alongside apply/remove
    /// (same-file access to the private(set) tally).
    mutating func notePlaceObject(version: Int) {
        switch version {
        case 1: tally.placeObject += 1
        case 2: tally.placeObject2 += 1
        default: tally.placeObject3 += 1
        }
    }

    mutating func noteShowFrame() {
        tally.showFrames += 1
    }

    mutating func noteDanglingPlacement() {
        tally.danglingPlacements += 1
    }
}
