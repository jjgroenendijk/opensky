// Turns a game-data path into something the renderer can draw: container parse,
// character dictionary and frame-1 display list, then font substitution through
// Interface\fontconfig.txt. The CLI and the app share it. The fontconfig
// environment is decoded once and cached, because the fontlib movies are large.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF

nonisolated public final class SWFMovieLoader {
    /// Archive path prefix + suffix of the movies the loader enumerates. VFS
    /// paths are archive-style (backslash separated, lowercased).
    public static let interfacePrefix = "interface\\"
    public static let movieSuffix = ".swf"
    public static let fontConfigPath = "interface\\fontconfig.txt"

    /// A decoded fontconfig plus the fontlib movies it names.
    public struct FontEnvironment: Sendable {
        public let config: SWFFontConfig
        public let library: SWFFontLibrary
    }

    private let fileSystem: VirtualFileSystem
    private var cachedFonts: FontEnvironment?
    /// Movies decoded to answer an ImportAssets URL, kept for the loader's
    /// lifetime: sibling menus import the same component movies, and a source
    /// nobody can provide is cached as a miss too.
    private var cachedSources: [String: SWFMovie?] = [:]

    public init(fileSystem: VirtualFileSystem) {
        self.fileSystem = fileSystem
    }

    /// Every `Interface\*.swf` movie in the mounted archives, path-sorted so a
    /// sweep or a picker lists them in a stable order.
    public func moviePaths() -> [String] {
        fileSystem.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(Self.interfacePrefix) && $0.hasSuffix(Self.movieSuffix) }
            .sorted()
    }

    /// Decodes one movie, merges the characters it imports, and resolves the fonts
    /// its edit texts need. Throws when the movie cannot be decoded; a missing source
    /// movie or font is recorded, not fatal. Imports merge first, so imported edit
    /// texts get fonts too.
    public func load(path: String) throws -> SWFMovieScene {
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
    public func fontEnvironment() -> FontEnvironment {
        if let cachedFonts {
            return cachedFonts
        }
        let environment = makeFontEnvironment()
        cachedFonts = environment
        return environment
    }

    private func makeFontEnvironment() -> FontEnvironment {
        guard let data = try? fileSystem.contents(forPath: Self.fontConfigPath) else {
            return FontEnvironment(config: SWFFontConfig.parse(""), library: SWFFontLibrary())
        }
        let text = GameText.decode(data)
        let config = SWFFontConfig.parse(text)
        var library = SWFFontLibrary()
        for movie in config.fontlibs {
            // fontlib names are install-relative paths ("Interface\fonts_en.swf");
            // the VFS normalizes case and separators.
            if let file = try? SWFFile(data: fileSystem.contents(forPath: movie)) {
                library.register(movie: movie, file: file)
            }
        }
        return FontEnvironment(config: config, library: library)
    }
}
