// App side of `MoviePlayerCoordinator`: the renderer draws the picture, the audio
// engine plays the sound, and `Game.PlayBink` waits on the movie. See
// docs/engine/movies.md.

import Foundation
public import OpenSkyAudio
public import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyMenus
public import OpenSkyMenusInterface
public import OpenSkyRendering
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld

/// What `MovieWorldAdapter` reads from the session. `GameSessionScope` conforms.
@MainActor
public protocol MovieWorldHost: AnyObject, SendableMetatype {
    var audio: any AudioPort { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var movies: any MoviePlayerPort { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
}

public final class MovieWorldAdapter: MoviePlayerWorld {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Movies"
    )
    /// The logo the game plays before the title menu.
    public static let startupLogo = "BGS_Logo.bik"

    public let game: any MovieWorldHost
    private var soundID: Int?
    /// The categories this movie muted, unmuted again when it ends.
    private var mutedCategories: [AudioCategory] = []

    public init(game: any MovieWorldHost) {
        self.game = game
    }

    public var movieFiles: (any GameFileSource)? {
        game.audioFileSystem
    }

    public func showMoviePicture(_ picture: MoviePicture?, letterbox: Bool) {
        game.renderer?.setMoviePicture(picture, letterbox: letterbox)
    }

    public func startMovieSound(_ sound: DecodedAudio?, request: MovieRequest) {
        guard let engine = game.audio.engine, engine.isRunning else { return }
        // [WARNING] Not confirmed which categories "game audio" covers; the movie plays
        // as an effect, so the effects category stays on.
        let muting = (request.muteAudio ? [AudioCategory.voice, .footsteps] : [])
            + (request.muteMusic ? [AudioCategory.music] : [])
        mutedCategories = muting.filter { !engine.isMuted($0) }
        for category in mutedCategories {
            engine.setMuted(true, for: category)
        }
        guard let sound, sound.frameCount > 0 else { return }
        do {
            let buffer = try WorldAudioEngine.makeBuffer(decoded: sound, downmixToMono: false)
            soundID = try engine.playNonPositional(
                buffer: buffer,
                request: .nonPositional(name: request.fileName, category: .effects)
            )
        } catch {
            let reason = String(describing: error)
            Self.logger.warning("[WARNING] movie sound did not start: \(reason, privacy: .public)")
        }
    }

    public func endMovieSound() {
        guard let engine = game.audio.engine else { return }
        if let soundID {
            engine.stopSource(id: soundID)
        }
        soundID = nil
        for category in mutedCategories {
            engine.setMuted(false, for: category)
        }
        mutedCategories = []
    }

    /// Plays the startup logo, then runs `then`. Runs `then` at once when the logo
    /// cannot play.
    public func playStartupLogo(then: @escaping () -> Void) {
        let request = MovieRequest(fileName: Self.startupLogo, interruptible: true)
        if !game.movies.play(request, onEnd: { _ in then() }) {
            then()
        }
    }

    /// `Game.PlayBink` waits on the movie; the call returns once it ends.
    public func playBink(_ request: PapyrusBinkRequest, waitToken token: UInt64) -> Bool {
        let movie = MovieRequest(
            fileName: request.fileName, interruptible: request.interruptible,
            muteAudio: request.muteAudio, muteMusic: request.muteMusic,
            letterbox: request.letterbox
        )
        return game.movies.play(movie) { [weak self] _ in
            self?.game.scripts.answer(token, returning: .none)
        }
    }
}

extension MovieWorldAdapter: MovieWorldPort {}
