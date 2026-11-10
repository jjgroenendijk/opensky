// Sound files are read from the archives and parsed off the main actor. A play
// whose file has not arrived starts after the drain that brings it, with the
// request it was made with. See docs/decisions/concurrency.md.

public import Foundation
public import OpenSkyFormatsAudio
public import OpenSkyGameData

/// A sound file read and parsed, ready for the engine.
nonisolated public enum AudioFileAsset: Sendable {
    case wav(WAVFile)
    case xwm(XWMFile)

    public init(data: Data) throws {
        self = Self.isWAV(data) ? try .wav(WAVFile(data: data)) : try .xwm(XWMFile(data: data))
    }

    /// True when `data` is a RIFF/WAVE form rather than a RIFF/XWMA one. The
    /// two share the RIFF header and differ in the form type at byte 8, so a
    /// twelve-byte peek decides which player path a file takes without parsing
    /// either container.
    static func isWAV(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let start = data.startIndex
        let magic = data[start ..< start + 4]
        let form = data[(start + 8) ..< (start + 12)]
        return magic.elementsEqual(Array("RIFF".utf8))
            && form.elementsEqual(Array("WAVE".utf8))
    }

    public var channelCount: Int {
        switch self {
        case let .wav(file): file.format.channelCount
        case let .xwm(file): file.codec.channelCount
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

    /// Reads from `files` on the shared play-time queue. Sounds are not cached:
    /// the asset cache measured no gain for them (docs/engine/asset-cache.md).
    public init(files: any GameFileSource) {
        source = .worker(AssetLoader { path in
            try AudioFileAsset(data: files.contents(forPath: path))
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
        }
    }
}
