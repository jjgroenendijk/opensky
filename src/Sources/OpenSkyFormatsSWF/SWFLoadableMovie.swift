// A movie another movie loads into a clip with `MovieClipLoader.loadClip`, merged in when
// the loading movie is loaded (docs/formats/swf-display-list.md#loaded-movies).

/// The loaded movie's root timeline as a sprite of the loading movie, and the
/// DoInitAction blocks that run before its first frame.
nonisolated public struct SWFLoadableMovie: Equatable, Sendable {
    public let spriteId: UInt16
    public let initActions: [SWFDoInitAction]
}

nonisolated extension SWFMovie {
    /// Every string the actions push or keep in a constant pool that ends in `.swf`,
    /// lowercased and sorted. These are the movies a `loadClip` call can name.
    var loadedMovieNames: [String] {
        var names: Set<String> = []
        for block in actionBlocks {
            for record in block.records {
                switch record.operands {
                case let .constantPool(strings):
                    names.formUnion(strings.filter(Self.namesMovie).map { $0.lowercased() })
                case let .push(values):
                    for case let .string(text) in values where Self.namesMovie(text) {
                        names.insert(text.lowercased())
                    }
                default:
                    continue
                }
            }
        }
        return names.sorted()
    }

    /// The sprite and init actions of the merged movie `url` names, case-insensitive.
    func loadedSprite(named url: String) -> (spriteId: UInt16, initActions: [SWFDoInitAction])? {
        loadableMovies[url.lowercased()].map { ($0.spriteId, $0.initActions) }
    }

    private static func namesMovie(_ text: String) -> Bool {
        text.lowercased().hasSuffix(".swf") && !text.contains(":")
    }
}
