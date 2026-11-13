// `MovieClipLoader.loadClip` of another interface movie: each `.swf` name in a
// movie's actions merges like an import, and its root becomes a sprite
// (docs/formats/swf-display-list.md#loaded-movies).

import Foundation

nonisolated extension SWFMovieImportMerger {
    /// Merges every other movie `movie`'s actions name with a `.swf` string, so
    /// `MovieClipLoader.loadClip` can put one in a clip and the renderer builds its
    /// shapes with the rest. A name that resolves to no movie is skipped.
    public static func mergeLoadables(
        _ movie: SWFMovie,
        path: String,
        resolve: @escaping Resolver
    ) -> SWFMovie {
        let own = Self.split(path).joined(separator: "\\")
        let names = movie.loadedMovieNames.filter {
            Self.resolvedPath(for: $0, relativeTo: path) != own
        }
        guard !names.isEmpty else {
            return movie
        }
        var merger = SWFMovieImportMerger(movie: movie, resolve: resolve)
        merger.diagnostics = movie.importDiagnostics
        merger.visiting.insert(own)
        for name in names {
            merger.mergeLoadable(name, path: own)
        }
        merger.movie.importDiagnostics = merger.diagnostics
        return merger.movie
    }

    private mutating func mergeLoadable(_ name: String, path: String) {
        guard
            let resolved = Self.resolvedPath(for: name, relativeTo: path),
            let source = resolve(resolved)
        else {
            diagnostics.missingSourceMovies += 1
            return
        }
        let highest = Int(Self.highestId(of: source))
        guard nextOffset + highest + 1 <= Int(UInt16.max) else {
            diagnostics.idSpaceOverflows += 1
            return
        }
        let offset = nextOffset
        nextOffset += highest + 2
        let firstImported = importedInitActions.count
        visiting.insert(resolved)
        _ = absorb(source, path: resolved, offset: offset)
        mergeImports(of: source, path: resolved, offset: offset, depth: 1)
        visiting.remove(resolved)
        var remap = SWFCharacterRemap(offset: offset)
        let spriteId = UInt16(offset + highest + 1)
        movie.characters[spriteId] = .sprite(SWFSprite(
            characterId: spriteId,
            frameCount: source.frameCount,
            timeline: remap.timeline(source.timeline)
        ))
        diagnostics.saturatedReferences += remap.saturatedReferences
        movie.loadableMovies[name] = SWFLoadableMovie(
            spriteId: spriteId,
            initActions: Array(importedInitActions[firstImported...])
                + initActions(of: source, offset: offset)
        )
    }
}
