// What the movie player plays: a request, a clock, and a source of decoded pictures.
// The Bink source decodes off the main actor. See docs/engine/movies.md.

public import Foundation
public import OpenSkyAudio
public import OpenSkyFormatsAudio
public import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyMenusInterface
import Synchronization

/// Which picture is due at a time since the first one showed.
nonisolated public struct MovieClock: Equatable, Sendable {
    public let framesPerSecond: Double
    public let frameCount: Int

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
