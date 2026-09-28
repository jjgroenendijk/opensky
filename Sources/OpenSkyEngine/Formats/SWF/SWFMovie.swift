// Movie model for the display-list renderer (milestone 8.2.4): the character
// dictionary (shapes, bitmaps, fonts, texts, edit texts, sprites) plus the
// frame-1 display list — every place/modify/remove tag applied up to the
// first ShowFrame. Sprite characters (DefineSprite, 39) decode their own
// nested tag stream and keep their own frame-1 list; rendering nested sprites
// beyond frame 1 (timeline animation) is 8.3.x work.
//
// Milestone 8.3.1 adds the action side without executing any of it: the main
// movie and every sprite keep a full `SWFTimeline` (all frames, each with its
// control tags and DoAction blocks), DoInitAction (59) blocks are collected by
// sprite id, and PlaceObject2/3 CLIPACTIONS handlers hang off their placement.
//
// Reference: Adobe SWF File Format Specification, version 19 — chapter 3
// "The display list" (pp. 33-51), chapter 5 "Actions" (pp. 63-118), and
// DefineSprite (chapter 13, p. 201).

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

/// A DefineSprite character: its declared frame count plus its own timeline
/// (nested placements resolved by depth like the main timeline, and the action
/// blocks of every frame).
nonisolated struct SWFSprite {
    let characterId: UInt16
    let frameCount: UInt16
    let timeline: SWFTimeline

    /// The sprite's frame-1 display list, depth-ascending.
    var frame1: [SWFPlacedObject] {
        timeline.frame1
    }
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

    // The counters above describe frame 1 only, because that is all the
    // renderer draws. The action counters below describe the whole movie —
    // every frame of the main timeline and of every sprite, plus DoInitAction
    // and CLIPACTIONS — because the 8.3.1 inventory is about what the bytecode
    // uses, not about what frame 1 shows.

    /// Action streams found anywhere in the movie: DoAction (12), DoInitAction
    /// (59), and PlaceObject2/3 CLIPACTIONS handlers.
    var actionBlocks = 0
    /// ACTIONRECORDs framed across those streams (the terminating
    /// `ActionEndFlag` is not a record and is not counted).
    var actionRecords = 0
    /// Records whose `ActionCode` is not in the Adobe action table.
    var unknownActionOpcodes = 0
    /// Records with an operand payload this stage frames but does not decode
    /// into typed operands. Their bytes are retained either way.
    var undecodedActionOpcodes = 0
    /// Action-stream framing problems recorded instead of thrown.
    var actionWarnings = 0

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
        actionBlocks += other.actionBlocks
        actionRecords += other.actionRecords
        unknownActionOpcodes += other.unknownActionOpcodes
        undecodedActionOpcodes += other.undecodedActionOpcodes
        actionWarnings += other.actionWarnings
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
    /// SWF version of the source file. CLIPEVENTFLAGS width depends on it, and
    /// so will the action model a later interpreter accepts.
    let version: UInt8
    let frameSize: SWFRect
    let frameCount: UInt16
    /// Header `FrameRate` in frames per second. The AS2 timer natives convert a
    /// millisecond interval into ticks with it, so `setInterval` stays a
    /// function of the movie rather than of a clock.
    let frameRate: Float
    /// SetBackgroundColor (9); nil when the movie never sets one.
    let backgroundColor: SWFColor?
    /// The character dictionary. `var` because the cross-movie import merge
    /// (`SWFMovieImportMerger`) folds imported characters in after decoding;
    /// nothing else writes it, and the movie stays a value type.
    var characters: [UInt16: SWFCharacter]
    /// The main timeline: every frame's control tags and DoAction blocks.
    let timeline: SWFTimeline
    /// DoInitAction (59) blocks in tag order. Each names the sprite whose first
    /// instantiation its actions precede; the spec allows at most one per
    /// sprite, which is not enforced here. The import merge prepends the blocks
    /// of every merged source movie, so an imported class is registered before
    /// anything instantiates it.
    var initActions: [SWFDoInitAction]
    /// Characters this movie imports by name (ImportAssets/ImportAssets2):
    /// character id -> export name in the source movie. Vanilla movies import
    /// their fonts this way, so an edit text's FontID often lands here rather
    /// than in `characters`. The import merge adds the tables of every merged
    /// source movie, so a merged edit text still finds its font substitution.
    var importedNames: [UInt16: String]
    /// Every ImportAssets/ImportAssets2 tag with its source movie URL. A font
    /// import is answered by substitution (`SWFMovieScene.resolvedFont`); a
    /// sprite import needs the source movie itself, which is why the URL is
    /// kept rather than folded away into `importedNames`.
    let imports: [SWFImportedAssets]
    /// Characters this movie exports by name (ExportAssets): linkage name ->
    /// character id. `Object.registerClass` binds a class to a linkage name, so
    /// this is the table that turns a registered class into something the
    /// display list can instantiate. An imported linkage name is added by the
    /// merge only when this movie does not already claim it.
    var exportedNames: [String: UInt16]
    /// The same table read the other way: character id -> linkage name. A
    /// placement carries an id, so this is the direction instantiation needs.
    /// Duplicate exports of one id keep the alphabetically first name, which
    /// makes the map deterministic. The merge also files each bound placeholder
    /// id here under the name it was imported by.
    var exportedIds: [UInt16: String]
    let tally: SWFMovieTally
    /// What the cross-movie import merge did, or an empty record when the movie
    /// imports nothing that needs merging. Counters only, never a throw.
    var importDiagnostics = SWFImportMergeDiagnostics()

    /// Main-timeline display list at the first ShowFrame, depth-ascending.
    var frame1: [SWFPlacedObject] {
        timeline.frame1
    }

    /// Every action stream the movie carries, in a stable order: the main
    /// timeline frame by frame, then each sprite's timeline (character id
    /// ascending), then the DoInitAction blocks in tag order. Within a frame,
    /// its DoAction blocks come before the CLIPACTIONS handlers of its
    /// placements. A consumer walks a block with `SWFActionBlock.records` and
    /// seeks by byte offset with `SWFActionBlock.record(atOffset:)`.
    var actionBlocks: [SWFActionBlock] {
        var blocks = timeline.actionBlocks
        for characterId in characters.keys.sorted() {
            if case let .sprite(sprite) = characters[characterId] {
                blocks += sprite.timeline.actionBlocks
            }
        }
        return blocks + initActions.map(\.actions)
    }

    init(file: SWFFile) throws {
        version = file.version
        frameSize = file.frameSize
        frameCount = file.frameCount
        frameRate = file.frameRate
        let jpegTables = file.tags
            .first { $0.code == SWFBitmapDecoder.jpegTablesTagCode }?.body
        var decoder = SWFMovieDecoder(version: file.version, jpegTables: jpegTables)
        try decoder.run(tags: file.tags)
        backgroundColor = decoder.timeline.backgroundColor
        characters = decoder.characters
        importedNames = decoder.importedNames
        imports = decoder.imports
        exportedNames = decoder.exportedNames
        var byId: [UInt16: String] = [:]
        for name in decoder.exportedNames.keys.sorted() {
            guard let id = decoder.exportedNames[name], byId[id] == nil else { continue }
            byId[id] = name
        }
        exportedIds = byId
        initActions = decoder.initActions
        let mainTimeline = decoder.timeline.finish()
        timeline = mainTimeline
        var total = mainTimeline.tally
        total.add(mainTimeline.actionTally)
        total.add(decoder.spriteTally)
        for initAction in decoder.initActions {
            total.record(actions: initAction.actions)
        }
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

nonisolated extension SWFDisplayListBuilder {
    /// Tally-only notes recorded by the timeline decoder alongside apply/remove.
    /// They live here because `tally` is `private(set)`, which limits its setter
    /// to this file.
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
