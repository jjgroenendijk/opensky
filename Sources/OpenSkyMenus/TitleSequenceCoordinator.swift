// The opening titles: `Interface\titles.swf` over the world, on the overlay layer, so the
// HUD keeps the main layer. `Game.ShowTitleSequenceMenu` opens it and
// `Game.StartTitleSequence` plays one of its clips. See docs/engine/main-menu.md#new-game.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

/// The measured contract of `titles.swf`: its first frame stops the clips `sequence1` to
/// `sequence4` on their own first frame, and `play()` runs one through.
nonisolated public enum TitleSequenceMovieBridge: Sendable {
    public static let moviePath = "interface\\titles.swf"
    public static let sequenceNames = ["sequence1", "sequence2", "sequence3", "sequence4"]

    /// The clip a script names, matched without case: MQ101 asks for "Sequence1".
    public static func clipPath(for sequence: String) -> String? {
        let name = sequence.lowercased()
        return sequenceNames.contains(name) ? "_root.\(name)" : nil
    }

    public static func play(_ clipPath: String, runtime: SWFMovieRuntime) {
        _ = runtime.callMovie("play", atPath: clipPath)
    }
}

public final class TitleSequenceCoordinator {
    public private(set) var isShown = false
    /// The clip asked for last, such as "sequence2".
    public private(set) var lastSequence: String?
    public let overlay: MenuMovieOverlay
    /// A clip asked for before the movie loaded, played once it is up.
    private var pendingClip: String?

    public init(movies: SWFMovieSource?, renderer: @escaping () -> Renderer?) {
        overlay = MenuMovieOverlay(movies: movies, renderer: renderer)
    }

    public var isLoaded: Bool {
        overlay.isLoaded
    }

    public func show(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        pendingClip = nil
        guard shown else {
            overlay.stop()
            return
        }
        overlay.start(path: TitleSequenceMovieBridge.moviePath) { [weak self] runtime in
            guard let self, let clip = pendingClip else { return }
            pendingClip = nil
            TitleSequenceMovieBridge.play(clip, runtime: runtime)
        }
    }

    /// Plays the named clip. False for a name the movie does not have, or while the
    /// movie is not shown.
    @discardableResult
    public func start(_ sequence: String) -> Bool {
        guard isShown, let clip = TitleSequenceMovieBridge.clipPath(for: sequence) else {
            return false
        }
        lastSequence = sequence.lowercased()
        guard overlay.isLoaded else {
            pendingClip = clip
            return true
        }
        overlay.update { TitleSequenceMovieBridge.play(clip, runtime: $0) }
        return true
    }

    public func tick() {
        overlay.tick()
    }
}
