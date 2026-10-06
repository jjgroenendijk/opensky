// Sound files are read from the archives and parsed off the main actor. A play
// whose file has not arrived starts after the drain that brings it, with the
// request it was made with. See docs/decisions/concurrency.md.

import Foundation
import OpenSkyAssetCache
import OpenSkyFormatsAudio
import OpenSkyGameData

/// A sound file read and parsed, ready for the engine.
nonisolated public enum AudioFileAsset: Sendable {
    case wav(WAVFile)
    case xwm(XWMFile)
    /// A cached file, decoded whole by macOS. Only short sounds are cached.
    case decoded(DecodedAudio)

    public init(data: Data) throws {
        self = WorldAudioEngine
            .isWAV(data) ? try .wav(WAVFile(data: data)) : try .xwm(XWMFile(data: data))
    }

    public var channelCount: Int {
        switch self {
        case let .wav(file): file.format.channelCount
        case let .xwm(file): file.codec.channelCount
        case let .decoded(audio): audio.channelCount
        }
    }
}

/// Loads sound files by path and keeps them, so a repeated effect is not read again.
public final class AudioAssetLoader {
    public typealias Use = (Result<AudioFileAsset, AssetLoadFailure>) -> Void

    private enum Source {
        case worker(AssetLoader<String, AudioFileAsset>)
        /// Loads on the caller, for tests and tools without a frame loop.
        case immediate((String) throws -> Data)
    }

    private let source: Source
    private var waiting: [(path: String, use: Use)] = []

    /// Reads from `files` on the shared play-time queue.
    public convenience init(files: any GameFileSource) {
        self.init(files: files, cache: nil)
    }

    /// Reads from `cache` when it holds a current copy, else from `files`.
    public init(files: any GameFileSource, cache: AssetCacheReader?) {
        source = .worker(AssetLoader { path in
            if let audio = cache?.value(forPath: path, decoder: .cachedAudio) {
                return .decoded(audio)
            }
            return try AudioFileAsset(data: files.contents(forPath: path))
        })
    }

    public init(immediate load: @escaping (String) throws -> Data) {
        source = .immediate(load)
    }

    /// Calls `use` now when the file is known, else after the drain that brings it.
    public func request(_ path: String, then use: @escaping Use) {
        switch source {
        case let .immediate(load):
            use(Result { try AudioFileAsset(data: load(path)) }.mapError(AssetLoadFailure.init))
        case let .worker(loader):
            switch loader.state(of: path) {
            case let .ready(asset): use(.success(asset))
            case let .failed(failure): use(.failure(failure))
            case .loading: waiting.append((path, use))
            }
        }
    }

    /// Takes finished files in and starts the plays that waited for them, oldest first.
    public func drain() {
        guard case let .worker(loader) = source else { return }
        loader.drain()
        let pending = waiting
        waiting = []
        for entry in pending {
            switch loader.state(of: entry.path) {
            case let .ready(asset): entry.use(.success(asset))
            case let .failed(failure): entry.use(.failure(failure))
            case .loading: waiting.append(entry)
            }
        }
    }
}

extension WorldAudioEngine {
    /// Starts a positional source from a parsed file. A `.wav` effect plays from one
    /// buffer; an `.xwm` file streams through the decode queue.
    @discardableResult
    public func playPositional(asset: AudioFileAsset, request: AudioPlayRequest) throws -> Int {
        switch asset {
        case let .wav(file):
            try playPositional(
                buffer: Self.makeBuffer(wav: file, downmixToMono: true),
                request: request
            )
        case let .xwm(file):
            try playPositional(file: file, request: request)
        case let .decoded(audio):
            try playPositional(
                buffer: Self.makeBuffer(decoded: audio, downmixToMono: true),
                request: request
            )
        }
    }

    @discardableResult
    public func playNonPositional(asset: AudioFileAsset, request: AudioPlayRequest) throws -> Int {
        switch asset {
        case let .wav(file):
            try playNonPositional(
                buffer: Self.makeBuffer(wav: file, downmixToMono: false), request: request
            )
        case let .xwm(file):
            try playNonPositional(file: file, request: request)
        case let .decoded(audio):
            try playNonPositional(
                buffer: Self.makeBuffer(decoded: audio, downmixToMono: false),
                request: request
            )
        }
    }
}
