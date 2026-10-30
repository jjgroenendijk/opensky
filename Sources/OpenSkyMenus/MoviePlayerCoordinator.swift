// Plays one movie over everything, for `Game.PlayBink` and the logo before the title
// menu. It opens a pausing menu, so the world and Papyrus stop while it plays, as the
// game does. See docs/engine/movies.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyGameData

/// What the movie player reaches outside itself. The app conforms.
public protocol MoviePlayerWorld: AnyObject {
    var movieFiles: (any GameFileSource)? { get }
    func showMoviePicture(_ picture: MoviePicture?, letterbox: Bool)
    func startMovieSound(_ sound: DecodedAudio?, request: MovieRequest)
    func endMovieSound()
}

nonisolated public enum MovieOutcome: Equatable, Sendable {
    case finished
    case skipped
    case failed(String)
}

nonisolated public struct MoviePlaybackReadout: Equatable, Sendable {
    public var fileName: String?
    public var loading: Bool
    /// The frame on screen, nil before the first one.
    public var frame: Int?
    public var frameCount: Int?
    public var interruptible: Bool
    public var lastOutcome: MovieOutcome?
}

public final class MoviePlayerCoordinator {
    /// OpenSky's own name: the game plays a movie outside its menu system.
    public static let identifier = MenuIdentifier("BinkMovie")
    /// Frames decoded ahead of the one on screen.
    static let lookahead = 3

    typealias FrameWorker = any AssetLoadWorking<Int, MoviePicture?>

    private struct Playback {
        let request: MovieRequest
        let clock: MovieClock
        let worker: FrameWorker
        let sound: DecodedAudio?
        var startedAt: Double?
        var nextRequest = 0
        var ready: [Int: MoviePicture?] = [:]
        var shown: Int?
    }

    private let menuMode: MenuModeController
    private weak var world: (any MoviePlayerWorld)?
    private let makeWorker: (any MovieFrameSource) -> FrameWorker
    private var pending: MovieRequest?
    private var playback: Playback?
    private var onEnd: ((MovieOutcome) -> Void)?
    private var lastOutcome: MovieOutcome?

    public convenience init(menuMode: MenuModeController, world: any MoviePlayerWorld) {
        self.init(menuMode: menuMode, world: world) { frames in
            SerialAssetLoadWorker { try frames.picture(ofFrame: $0) }
        }
    }

    init(
        menuMode: MenuModeController, world: any MoviePlayerWorld,
        makeWorker: @escaping (any MovieFrameSource) -> FrameWorker
    ) {
        self.menuMode = menuMode
        self.world = world
        self.makeWorker = makeWorker
    }

    public var isPlaying: Bool {
        pending != nil || playback != nil
    }

    /// Opens the movie; `onEnd` runs once it ends, is skipped, or fails. False while
    /// another movie plays or without game files.
    @discardableResult
    public func play(_ request: MovieRequest, onEnd: @escaping (MovieOutcome) -> Void) -> Bool {
        guard let files = world?.movieFiles, begin(request, onEnd: onEnd) else { return false }
        Task { [weak self] in
            let result: Result<LoadedMovie, any Error>
            do {
                result = try await .success(BinkMovieFrames.open(request, files: files))
            } catch {
                result = .failure(error)
            }
            self?.opened(result, for: request)
        }
        return true
    }

    /// Opens the menu; the movie starts once `opened` hands it over.
    func begin(_ request: MovieRequest, onEnd: @escaping (MovieOutcome) -> Void) -> Bool {
        guard !isPlaying else { return false }
        pending = request
        self.onEnd = onEnd
        menuMode.present(Self.identifier)
        return true
    }

    func opened(_ result: Result<LoadedMovie, any Error>, for request: MovieRequest) {
        guard pending == request else { return }
        pending = nil
        switch result {
        case let .success(movie): start(movie, request: request)
        case let .failure(error): finish(.failed(String(describing: error)))
        }
    }

    private func start(_ movie: LoadedMovie, request: MovieRequest) {
        guard movie.frames.clock.frameCount > 0, movie.frames.clock.framesPerSecond > 0 else {
            finish(.failed("the movie has no frames"))
            return
        }
        playback = Playback(
            request: request, clock: movie.frames.clock, worker: makeWorker(movie.frames),
            sound: movie.sound
        )
        requestFrames(through: 0)
    }

    /// Ends the movie early. Only an interruptible one, unless `force`.
    @discardableResult
    public func skip(force: Bool = false) -> Bool {
        guard let request = playback?.request ?? pending, force || request.interruptible else {
            return false
        }
        finish(.skipped)
        return true
    }

    public func route(_ event: MenuInputEvent) {
        // [WARNING] Not confirmed which keys skip a movie; cancel and accept both do here.
        if event == .button(.cancel) || event == .button(.accept) {
            skip()
        }
    }

    public func tick(now: Double) {
        guard var current = playback else { return }
        for completion in current.worker.takeFinished() {
            switch completion.result {
            case let .success(picture): current.ready[completion.key] = picture
            case let .failure(failure):
                finish(.failed(failure.reason))
                return
            }
        }
        if current.startedAt == nil, current.ready[0] != nil {
            current.startedAt = now
            world?.startMovieSound(current.sound, request: current.request)
        }
        guard let startedAt = current.startedAt else {
            playback = current
            return
        }
        let elapsed = now - startedAt
        if current.clock.hasEnded(at: elapsed) {
            playback = current
            finish(.finished)
            return
        }
        let due = current.clock.frame(at: elapsed)
        if let newest = current.ready.keys.filter({ $0 <= due }).max() {
            if case let .some(.some(picture)) = current.ready[newest] {
                world?.showMoviePicture(picture, letterbox: current.request.letterbox)
            }
            current.shown = newest
            current.ready = current.ready.filter { $0.key > newest }
        }
        playback = current
        requestFrames(through: due)
    }

    public var readout: MoviePlaybackReadout {
        MoviePlaybackReadout(
            fileName: (playback?.request ?? pending)?.fileName,
            loading: pending != nil,
            frame: playback?.shown,
            frameCount: playback?.clock.frameCount,
            interruptible: (playback?.request ?? pending)?.interruptible ?? false,
            lastOutcome: lastOutcome
        )
    }

    /// Keeps the worker `lookahead` frames past the one due, in frame order.
    private func requestFrames(through due: Int) {
        guard var current = playback else { return }
        let last = min(due + Self.lookahead, current.clock.frameCount - 1)
        while current.nextRequest <= last {
            current.worker.submit(current.nextRequest, priority: .needed)
            current.nextRequest += 1
        }
        playback = current
    }

    private func finish(_ outcome: MovieOutcome) {
        let started = playback?.startedAt != nil
        pending = nil
        playback = nil
        lastOutcome = outcome
        world?.showMoviePicture(nil, letterbox: true)
        if started {
            world?.endMovieSound()
        }
        menuMode.dismiss(Self.identifier)
        let ended = onEnd
        onEnd = nil
        ended?(outcome)
    }
}
