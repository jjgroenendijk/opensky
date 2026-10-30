// What the movie player plays: a request, a clock, and a source of decoded pictures.
// The Bink source decodes off the main actor. See docs/engine/movies.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsAudio
import OpenSkyFormatsCore
import OpenSkyGameData
import Synchronization

/// The arguments of `Game.PlayBink` (<https://ck.uesp.net/wiki/PlayBink_-_Game>).
nonisolated public struct MovieRequest: Equatable, Sendable {
    /// A file under `Data\Video`, such as `BGS_Logo.bik`.
    public var fileName: String
    public var interruptible: Bool
    public var muteAudio: Bool
    public var muteMusic: Bool
    public var letterbox: Bool

    public init(
        fileName: String, interruptible: Bool = false, muteAudio: Bool = true,
        muteMusic: Bool = true, letterbox: Bool = true
    ) {
        self.fileName = fileName
        self.interruptible = interruptible
        self.muteAudio = muteAudio
        self.muteMusic = muteMusic
        self.letterbox = letterbox
    }

    /// The path in the game's file system.
    public var path: String {
        let name = fileName.replacingOccurrences(of: "/", with: "\\")
        return name.lowercased().hasPrefix("video\\") ? name : "video\\" + name
    }
}

/// Which picture is due at a time since the first one showed.
nonisolated public struct MovieClock: Equatable, Sendable {
    public let framesPerSecond: Double
    public let frameCount: Int

    public init(framesPerSecond: Double, frameCount: Int) {
        self.framesPerSecond = framesPerSecond
        self.frameCount = frameCount
    }

    public var duration: Double {
        Double(frameCount) / framesPerSecond
    }

    public func frame(at elapsed: Double) -> Int {
        let frame = Int((max(elapsed, 0) * framesPerSecond).rounded(.down))
        return min(frame, frameCount - 1)
    }

    public func hasEnded(at elapsed: Double) -> Bool {
        elapsed >= duration
    }
}

/// Decodes pictures in frame order. Nil for a frame that changes nothing.
nonisolated public protocol MovieFrameSource: Sendable {
    var clock: MovieClock { get }
    func picture(ofFrame index: Int) throws -> MoviePicture?
}

/// An opened movie: its pictures and its whole sound track.
nonisolated public struct LoadedMovie: Sendable {
    public let frames: any MovieFrameSource
    public let sound: DecodedAudio?

    public init(frames: any MovieFrameSource, sound: DecodedAudio?) {
        self.frames = frames
        self.sound = sound
    }
}

/// A Bink file's video track. A frame builds on the one before, so the decoder sits in
/// a `Mutex` and the worker asks for frames in order.
nonisolated public final class BinkMovieFrames: MovieFrameSource {
    public let movie: BinkMovie
    private let data: Data
    private let decoder: Mutex<BinkVideoDecoder>

    public init(movie: BinkMovie, data: Data) throws {
        self.movie = movie
        self.data = data
        decoder = try Mutex(BinkVideoDecoder(movie: movie))
    }

    public var clock: MovieClock {
        MovieClock(framesPerSecond: movie.framesPerSecond, frameCount: movie.frames.count)
    }

    public func picture(ofFrame index: Int) throws -> MoviePicture? {
        let packet = try movie.packets(ofFrame: index, in: data).video
        return try decoder.withLock { try $0.decode(packet: packet) }
    }

    /// Reads, frames, and decodes the sound of `request`'s file.
    @concurrent
    public static func open(
        _ request: MovieRequest, files: any GameFileSource
    ) async throws -> LoadedMovie {
        let data = try files.contents(forPath: request.path)
        let movie = try BinkMovie(data: data)
        // [WARNING] Not confirmed: the game plays the track with ID 0 when a movie has two.
        let track = movie.audioTracks.firstIndex { $0.id == 0 } ?? movie.audioTracks.indices.first
        let sound = try track.map { try BinkAudioDecoder.decodeTrack($0, of: movie, data: data) }
        return try LoadedMovie(frames: BinkMovieFrames(movie: movie, data: data), sound: sound)
    }
}
