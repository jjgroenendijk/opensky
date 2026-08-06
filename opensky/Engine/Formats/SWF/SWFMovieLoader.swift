// One place to turn a game-data path into something the renderer can draw:
// container parse -> character dictionary + frame-1 display list -> external
// font substitution through Interface\fontconfig.txt. The CLI sweeps and the
// app's movie picker both go through this, so both see identical decoding and
// identical font resolution.
//
// The fontconfig environment (config + fontlib library) is decoded once on
// first use and cached for the loader's lifetime: the fontlib movies are large
// and shared by every Interface movie.

import Foundation

nonisolated final class SWFMovieLoader {
    /// Archive path prefix + suffix of the movies the loader enumerates. VFS
    /// paths are archive-style (backslash separated, lowercased).
    static let interfacePrefix = "interface\\"
    static let movieSuffix = ".swf"
    static let fontConfigPath = "interface\\fontconfig.txt"

    /// A decoded fontconfig plus the fontlib movies it names.
    struct FontEnvironment {
        let config: SWFFontConfig
        let library: SWFFontLibrary
        /// fontlib movies named by fontconfig that the VFS could not provide.
        let missingFontlibs: [String]
    }

    private let fileSystem: VirtualFileSystem
    private var cachedFonts: FontEnvironment?
    /// Movies decoded to answer an ImportAssets URL, kept for the loader's
    /// lifetime: sibling menus import the same component movies, and a source
    /// nobody can provide is cached as a miss too.
    private var cachedSources: [String: SWFMovie?] = [:]

    init(fileSystem: VirtualFileSystem) {
        self.fileSystem = fileSystem
    }

    /// Every `Interface\*.swf` movie in the mounted archives, path-sorted so a
    /// sweep or a picker lists them in a stable order.
    func moviePaths() -> [String] {
        fileSystem.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(Self.interfacePrefix) && $0.hasSuffix(Self.movieSuffix) }
            .sorted()
    }

    /// Decodes one movie, folds in the characters it imports from other movies,
    /// and resolves the fonts its edit texts need. Throws the underlying
    /// `SWFError`/parse error when the movie itself cannot be decoded; a source
    /// movie that cannot be provided and an unresolvable font name are both
    /// recorded rather than fatal.
    ///
    /// The import merge runs before font resolution so an edit text that came
    /// in with an imported sprite gets its substitution too.
    func load(path: String) throws -> SWFMovieScene {
        let file = try SWFFile(data: fileSystem.contents(forPath: path))
        let merged = try SWFMovieImportMerger.merge(
            SWFMovie(file: file),
            path: path,
            resolve: { [self] source in sourceMovie(at: source) }
        )
        var scene = SWFMovieScene(movie: merged)
        let fonts = fontEnvironment()
        scene.resolveExternalFonts(config: fonts.config, library: fonts.library)
        return scene
    }

    /// One import source, decoded on first request. Both an unreadable file and
    /// an undecodable movie cache as a miss, so a broken import costs one
    /// attempt rather than one per importing movie.
    private func sourceMovie(at path: String) -> SWFMovie? {
        if let cached = cachedSources[path] {
            return cached
        }
        let movie = (try? fileSystem.contents(forPath: path))
            .flatMap { try? SWFFile(data: $0) }
            .flatMap { try? SWFMovie(file: $0) }
        cachedSources[path] = movie
        return movie
    }

    /// The shared fontconfig environment, decoded on first use. A missing or
    /// unreadable fontconfig.txt yields an empty environment: movies with
    /// self-contained fonts still render, edit texts needing a substitution
    /// fall out with an `unresolvedFontNames` entry.
    func fontEnvironment() -> FontEnvironment {
        if let cachedFonts {
            return cachedFonts
        }
        let environment = makeFontEnvironment()
        cachedFonts = environment
        return environment
    }

    private func makeFontEnvironment() -> FontEnvironment {
        guard let data = try? fileSystem.contents(forPath: Self.fontConfigPath) else {
            return FontEnvironment(
                config: SWFFontConfig.parse(""), library: SWFFontLibrary(), missingFontlibs: []
            )
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252) ?? ""
        let config = SWFFontConfig.parse(text)
        var library = SWFFontLibrary()
        var missing: [String] = []
        for movie in config.fontlibs {
            // fontlib names are install-relative paths ("Interface\fonts_en.swf");
            // the VFS normalizes case and separators.
            if let file = try? SWFFile(data: fileSystem.contents(forPath: movie)) {
                library.register(movie: movie, file: file)
            } else {
                missing.append(movie)
            }
        }
        return FontEnvironment(config: config, library: library, missingFontlibs: missing)
    }
}
