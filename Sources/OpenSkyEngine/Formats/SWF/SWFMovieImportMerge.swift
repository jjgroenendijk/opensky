// Cross-movie character import (ImportAssets 57 / ImportAssets2 71): a movie
// that borrows a sprite from another movie gets that sprite's characters, its
// linkage names, and its DoInitAction class registrations folded into its own
// dictionary. `interface\inventorymenu.swf` places three characters it never
// defines — `ItemCard_mc`, `InventoryLists_mc`, `BottomBar_mc` — and without
// this merge each of them instantiates as nothing.
//
// The merge is a uniform-offset one at the `SWFMovie` level, so the runtime and
// the renderer stay unchanged: they still see one flat character dictionary.
// For each distinct source movie the whole source id space is shifted past
// everything already in flight (`SWFCharacterRemap`), the shifted characters and
// name tables are merged in, and the importing movie's placeholder id is bound
// to whatever the source exports under the imported name.
//
// Rules that are decisions rather than spec:
//   - On a linkage-name collision the importing movie wins. Its own bytecode
//     registered its classes against its own definitions.
//   - Source DoInitAction blocks run before the importing movie's own, deepest
//     import first, so an imported CLIK class is registered before anything
//     instantiates it.
//   - A URL whose assets the importing movie neither places nor re-exports is
//     skipped without being loaded. That is exactly the shape of a font import
//     (`gfxfontlib.swf`), and fonts keep their existing answer: name
//     substitution through fontconfig in `SWFMovieScene.resolvedFont`.
//   - Nothing here throws. Every failure — a source the file system cannot
//     provide, a name the source does not export, a cycle, an id space that
//     will not fit — is a bounded counter on `SWFImportMergeDiagnostics`.
//   - `SWFMovie.tally` is left alone. It describes what one file decoded to,
//     which is what the sweeps report; merged characters are counted on the
//     import diagnostics instead.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 14
// "Sharing fonts and other assets" (pp. 285-286).

import Foundation

/// Bounded counters describing one movie's import merge, in the
/// `SWFMovieTally` / `AS2Tally` tradition: counted, never thrown.
nonisolated struct SWFImportMergeDiagnostics: Equatable {
    /// Resolved paths named in `mergedPaths`; the counters keep counting past it.
    static let pathLimit = 32

    /// Source movies whose characters were merged in.
    var mergedMovies = 0
    /// Characters those movies contributed, after remapping.
    var mergedCharacters = 0
    /// Placeholder ids bound to a merged character.
    var boundPlaceholders = 0
    /// Imported names the source movie does not export, so the placeholder
    /// stays unresolved.
    var unresolvedPlaceholders = 0
    /// Import URLs the resolver could not turn into a decoded movie.
    var missingSourceMovies = 0
    /// Import URLs skipped as display-irrelevant (the font-import case).
    var skippedImports = 0
    /// Imports refused because the recursion bound was reached.
    var depthLimitHits = 0
    /// Imports refused because the source is already being merged (a cycle).
    var cyclicImports = 0
    /// Source movies refused because their shifted ids would leave `UInt16`.
    var idSpaceOverflows = 0
    /// Individual references that saturated at `UInt16.max` while shifting.
    var saturatedReferences = 0
    /// Resolved VFS paths merged, in merge order, capped at `pathLimit`.
    var mergedPaths: [String] = []

    /// True when the movie imported nothing that needed merging.
    var isEmpty: Bool {
        self == SWFImportMergeDiagnostics()
    }

    /// One-line report for the CLI.
    var summary: String {
        "\(mergedMovies) movies, \(mergedCharacters) characters, "
            + "\(boundPlaceholders) placeholders bound, "
            + "\(unresolvedPlaceholders) unresolved, \(missingSourceMovies) missing, "
            + "\(skippedImports) skipped, \(depthLimitHits) depth-bound, "
            + "\(cyclicImports) cyclic, \(idSpaceOverflows) id-space overflows"
    }

    mutating func note(path: String) {
        mergedMovies += 1
        if mergedPaths.count < Self.pathLimit {
            mergedPaths.append(path)
        }
    }
}

/// Folds the movies an importing movie names into it. Pure: the only outside
/// contact is the `Resolver` seam, which turns an already-resolved VFS path
/// into a decoded movie, so the merge unit-tests without a file system.
nonisolated struct SWFMovieImportMerger {
    /// Resolved VFS path -> decoded source movie, or nil when unavailable.
    typealias Resolver = (String) -> SWFMovie?

    /// How many import hops deep the merge follows. Vanilla menus need two;
    /// the bound only exists so a malformed chain terminates.
    static let maximumDepth = 4

    private let resolve: Resolver
    private var movie: SWFMovie
    /// Lowest id no merged movie has claimed yet.
    private var nextOffset: Int
    /// Resolved path -> that source's export table in merged ids. Doubles as
    /// the dedupe memo, so a diamond import merges once.
    private var exportsByPath: [String: [String: UInt16]] = [:]
    /// Paths on the current merge stack, so a cycle terminates.
    private var visiting: Set<String> = []
    /// Merged init actions in run order, deepest import first.
    private var importedInitActions: [SWFDoInitAction] = []
    private var diagnostics = SWFImportMergeDiagnostics()

    /// Merges every non-font import `movie` names, recursively.
    /// - Parameters:
    ///   - path: the importing movie's own VFS path; import URLs are relative
    ///     to its directory.
    ///   - resolve: loads and decodes one resolved VFS path.
    static func merge(
        _ movie: SWFMovie,
        path: String,
        resolve: @escaping Resolver
    ) -> SWFMovie {
        guard !movie.imports.isEmpty else {
            return movie
        }
        var merger = SWFMovieImportMerger(movie: movie, resolve: resolve)
        return merger.run(path: path)
    }

    private init(movie: SWFMovie, resolve: @escaping Resolver) {
        self.movie = movie
        self.resolve = resolve
        nextOffset = Int(Self.highestId(of: movie)) + 1
    }

    private mutating func run(path: String) -> SWFMovie {
        let root = Self.split(path).joined(separator: "\\")
        visiting.insert(root)
        mergeImports(of: movie, path: root, offset: 0, depth: 0)
        movie.initActions = importedInitActions + movie.initActions
        movie.importDiagnostics = diagnostics
        return movie
    }

    // MARK: - Merging

    /// Walks one movie's import tags. `offset` is the shift already applied to
    /// that movie's own ids, which is what turns its placeholder id into the
    /// merged dictionary key that has to be bound; `depth` is how many import
    /// hops that movie itself sits below the root.
    private mutating func mergeImports(
        of importer: SWFMovie,
        path: String,
        offset: Int,
        depth: Int
    ) {
        let displayed = Self.displayIds(of: importer)
        for tag in importer.imports {
            guard let resolved = Self.resolvedPath(for: tag.url, relativeTo: path) else {
                diagnostics.skippedImports += 1
                continue
            }
            guard tag.assets.contains(where: { displayed.contains($0.characterId) }) else {
                diagnostics.skippedImports += 1
                continue
            }
            guard let exports = exports(at: resolved, depth: depth + 1) else {
                continue
            }
            bind(tag, exports: exports, offset: offset)
        }
    }

    /// The export table of one source movie in merged ids, merging the movie
    /// on first sight. `depth` is that source's own hop count. nil when it
    /// cannot be merged at all.
    private mutating func exports(at path: String, depth: Int) -> [String: UInt16]? {
        if let cached = exportsByPath[path] {
            return cached
        }
        guard depth <= Self.maximumDepth else {
            diagnostics.depthLimitHits += 1
            return nil
        }
        guard !visiting.contains(path) else {
            diagnostics.cyclicImports += 1
            return nil
        }
        guard let source = resolve(path) else {
            diagnostics.missingSourceMovies += 1
            return nil
        }
        guard let offset = allocateOffset(for: source) else {
            diagnostics.idSpaceOverflows += 1
            return nil
        }
        visiting.insert(path)
        defer { visiting.remove(path) }
        let exports = absorb(source, path: path, offset: offset)
        // The source's own imports resolve after its characters are in place,
        // because binding one of its placeholders writes into the merged
        // dictionary.
        mergeImports(of: source, path: path, offset: offset, depth: depth)
        importedInitActions += initActions(of: source, offset: offset)
        return exports
    }

    /// Merges one source movie's characters and name tables at `offset` and
    /// returns its export table in merged ids.
    private mutating func absorb(
        _ source: SWFMovie,
        path: String,
        offset: Int
    ) -> [String: UInt16] {
        var remap = SWFCharacterRemap(offset: offset)
        let characters = remap.characters(source.characters)
        let exports = remap.exportedNames(source.exportedNames)
        let importedNames = remap.importedNames(source.importedNames)
        diagnostics.saturatedReferences += remap.saturatedReferences
        for (key, value) in characters {
            movie.characters[key] = value
        }
        for (name, id) in exports where movie.exportedNames[name] == nil {
            // The importing movie wins a linkage-name collision: its own
            // bytecode registered classes against its own definitions.
            movie.exportedNames[name] = id
        }
        for (id, name) in Self.namesById(exports) where movie.exportedIds[id] == nil {
            movie.exportedIds[id] = name
        }
        for (id, name) in importedNames where movie.importedNames[id] == nil {
            movie.importedNames[id] = name
        }
        diagnostics.mergedCharacters += characters.count
        diagnostics.note(path: path)
        exportsByPath[path] = exports
        return exports
    }

    private mutating func initActions(of source: SWFMovie, offset: Int) -> [SWFDoInitAction] {
        var remap = SWFCharacterRemap(offset: offset)
        let actions = remap.initActions(source.initActions)
        diagnostics.saturatedReferences += remap.saturatedReferences
        return actions
    }

    /// Points the importing movie's placeholder ids at the merged characters.
    /// The placeholder also takes the linkage name, because a placement carries
    /// the placeholder id and `SWFMovieRuntime.constructRegisteredClass` looks
    /// the registered class up by `exportedIds[characterId]`.
    private mutating func bind(
        _ tag: SWFImportedAssets,
        exports: [String: UInt16],
        offset: Int
    ) {
        var remap = SWFCharacterRemap(offset: offset)
        for asset in tag.assets {
            let placeholder = remap.id(asset.characterId)
            guard
                let sourceId = exports[asset.name],
                let character = movie.characters[sourceId]
            else {
                diagnostics.unresolvedPlaceholders += 1
                continue
            }
            movie.characters[placeholder] = character
            if movie.exportedIds[placeholder] == nil {
                movie.exportedIds[placeholder] = asset.name
            }
            diagnostics.boundPlaceholders += 1
        }
        diagnostics.saturatedReferences += remap.saturatedReferences
    }

    /// Reserves an id range for one source movie, or nil when its shifted ids
    /// would leave the 16-bit space.
    private mutating func allocateOffset(for source: SWFMovie) -> Int? {
        let highest = Int(Self.highestId(of: source))
        guard nextOffset + highest <= Int(UInt16.max) else {
            return nil
        }
        let offset = nextOffset
        nextOffset += highest + 1
        return offset
    }

    // MARK: - Pure helpers

    /// The highest character id a movie names anywhere, which is how wide an
    /// id range it needs.
    static func highestId(of movie: SWFMovie) -> UInt16 {
        var highest: UInt16 = 0
        for id in movie.characters.keys {
            highest = max(highest, id)
        }
        for id in movie.importedNames.keys {
            highest = max(highest, id)
        }
        for id in movie.exportedNames.values {
            highest = max(highest, id)
        }
        for action in movie.initActions {
            highest = max(highest, action.spriteId)
        }
        return highest
    }

    /// Character ids the movie actually puts on screen or re-exports: every
    /// placement in every timeline, main and sprite, plus its ExportAssets
    /// targets. An import naming none of these needs no merge — that is the
    /// font-import case, answered by substitution instead.
    static func displayIds(of movie: SWFMovie) -> Set<UInt16> {
        var ids = Set(movie.exportedNames.values)
        var timelines = [movie.timeline]
        for id in movie.characters.keys.sorted() {
            if case let .sprite(sprite) = movie.characters[id] {
                timelines.append(sprite.timeline)
            }
        }
        for timeline in timelines {
            for frame in timeline.frames {
                for case let .place(placement) in frame.steps {
                    if let id = placement.characterId {
                        ids.insert(id)
                    }
                }
            }
        }
        return ids
    }

    /// An import URL is relative to the importing movie's own directory and
    /// uses either separator ("Inventory components/ItemCard.swf" inside
    /// `interface\inventorymenu.swf` is `interface\inventory
    /// components\itemcard.swf`). The result is a canonical VFS key: lowercase,
    /// backslash separated. nil when the URL names nothing.
    static func resolvedPath(for url: String, relativeTo importer: String) -> String? {
        var components = Self.split(importer)
        if !components.isEmpty {
            components.removeLast()
        }
        for component in Self.split(url) {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(component)
            }
        }
        return components.isEmpty ? nil : components.joined(separator: "\\")
    }

    /// An export table read the other way. Duplicate exports of one id keep the
    /// alphabetically first name, matching `SWFMovie.exportedIds`.
    static func namesById(_ exports: [String: UInt16]) -> [UInt16: String] {
        var byId: [UInt16: String] = [:]
        for name in exports.keys.sorted() {
            guard let id = exports[name], byId[id] == nil else { continue }
            byId[id] = name
        }
        return byId
    }

    private static func split(_ path: String) -> [String] {
        path.lowercased()
            .replacingOccurrences(of: "/", with: "\\")
            .split(separator: "\\")
            .map(String.init)
    }
}
