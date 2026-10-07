// The values texture streaming moves between the build worker and the frame. The
// worker posts; the frame drains at one point and never waits.
// See docs/rendering/texture-streaming.md.

import Foundation
@preconcurrency import Metal
import OpenSkyAssetCache
import Synchronization

/// Where a streamed texture's bytes come from, so its levels can be read again.
nonisolated public struct TextureStreamSource: Hashable, Sendable {
    public let path: String
    public let usage: TextureUsage

    public init(path: String, usage: TextureUsage) {
        self.path = path
        self.usage = usage
    }
}

/// The bytes of some levels of one texture, smallest last.
nonisolated public struct TextureLevelBytes: Sendable {
    public let firstLevel: Int
    /// `ReadyTexture` packing: every level from `firstLevel` on, with no gaps.
    public let ready: ReadyTexture

    public init(firstLevel: Int, ready: ReadyTexture) {
        self.firstLevel = firstLevel
        self.ready = ready
    }

    public var levels: Range<Int> {
        firstLevel ..< firstLevel + ready.mipCount
    }

    /// `level` is a level of the whole texture.
    public func bytes(level: Int) -> Data {
        let range = ready.levelRange(level - firstLevel)
        return ready.bytes.subdata(
            in: ready.bytes.startIndex + range.lowerBound ..< ready.bytes.startIndex
                + range.upperBound
        )
    }

    public func bytesPerRow(level: Int) -> Int {
        ready.bytesPerRow(level: level - firstLevel)
    }

    /// Keeps the levels from `level` down to the smallest.
    public static func levels(of ready: ReadyTexture, from level: Int) -> TextureLevelBytes {
        let start = min(max(level, 0), ready.mipCount - 1)
        let range = ready.levelRange(start)
        let bytes = ready.bytes.subdata(
            in: ready.bytes.startIndex + range.lowerBound ..< ready.bytes.endIndex
        )
        return TextureLevelBytes(firstLevel: start, ready: ReadyTexture(
            format: ready.format, width: ready.width(level: start),
            height: ready.height(level: start), mipCount: ready.mipCount - start, bytes: bytes
        ))
    }
}

/// A new streamed texture: no tiles mapped yet, and the levels it starts with.
nonisolated public struct StreamedTextureSeed: Sendable {
    public let texture: MTLTexture
    public let source: TextureStreamSource
    public let layout: SparseTextureLayout
    public let levels: TextureLevelBytes
}

/// A request to read a streamed texture's levels from `firstLevel` on again.
nonisolated public struct TextureLevelRequest: Sendable {
    public let texture: MTLTexture
    public let source: TextureStreamSource
    public let firstLevel: Int
}

/// What reads levels again, off the main actor. The cell build worker in the game.
nonisolated public protocol TextureLevelReading: AnyObject {
    /// Returns at once; the levels arrive in `mailbox` later.
    func requestTextureLevels(_ request: TextureLevelRequest, mailbox: TextureStreamMailbox)
}

/// The settings a loader needs to create streamed textures.
nonisolated public struct TextureStreamingLoadSettings: Equatable, Sendable {
    public var enabled = false
    public var pageSize = MTLSparsePageSize.size16
    /// A texture streams only if its long side is at least this many texels.
    public var minimumSize = 512
    /// A new texture starts with levels no larger than this on the long side.
    public var initialSize = 512

    public init() {}
}

nonisolated public final class TextureStreamMailbox: Sendable {
    private struct State {
        var settings = TextureStreamingLoadSettings()
        var seeds: [StreamedTextureSeed] = []
        var deliveries: [(texture: MTLTexture, levels: TextureLevelBytes)] = []
    }

    private let state = Mutex(State())

    public init() {}

    public var loadSettings: TextureStreamingLoadSettings {
        get { state.withLock { $0.settings } }
        set { state.withLock { $0.settings = newValue } }
    }

    public func post(_ seed: StreamedTextureSeed) {
        state.withLock { $0.seeds.append(seed) }
    }

    public func post(levels: TextureLevelBytes, for texture: MTLTexture) {
        state.withLock { $0.deliveries.append((texture, levels)) }
    }

    func drainSeeds() -> [StreamedTextureSeed] {
        state.withLock { state in
            defer { state.seeds.removeAll(keepingCapacity: true) }
            return state.seeds
        }
    }

    func drainDeliveries() -> [(texture: MTLTexture, levels: TextureLevelBytes)] {
        state.withLock { state in
            defer { state.deliveries.removeAll(keepingCapacity: true) }
            return state.deliveries
        }
    }
}
