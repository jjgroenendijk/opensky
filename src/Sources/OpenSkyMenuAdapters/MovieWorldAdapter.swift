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
    /// What the playing movie holds: the master category, the music, or both.
    private var mutesAudio = false
    private var mutesMusic = false

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
        // The movie's own sound skips the categories and the master volume.
        mutesAudio = request.muteAudio
        mutesMusic = request.muteMusic
        if mutesAudio {
            engine.movieMutesAudio = true
        }
        if mutesMusic {
            game.audio.musicDirector?.pauseMusic()
        }
        guard let sound, sound.frameCount > 0 else { return }
        do {
            let buffer = try WorldAudioEngine.makeBuffer(decoded: sound, downmixToMono: false)
            var play = AudioPlayRequest.nonPositional(name: request.fileName, category: .effects)
            play.bypassesCategory = true
            soundID = try engine.playNonPositional(buffer: buffer, request: play)
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
        // Audio comes back first, then music.
        if mutesAudio {
            engine.movieMutesAudio = false
        }
        if mutesMusic {
            game.audio.musicDirector?.resumeMusic()
        }
        mutesAudio = false
        mutesMusic = false
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
