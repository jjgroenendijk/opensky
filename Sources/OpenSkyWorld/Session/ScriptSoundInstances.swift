// The sounds scripts started with `Sound.Play` and `Sound.PlayAndWait`, by the instance
// ID Papyrus holds (<https://ck.uesp.net/wiki/Play_-_Sound>). The engine source comes
// once the file loads, so a stop or a volume set before that waits for it. Pure.

import simd

nonisolated public struct ScriptSoundInstances: Equatable, Sendable {
    struct Instance: Equatable {
        var sourceID: Int?
        var volume: Float?
        var stopped = false
        /// The `PlayAndWait` call to answer when the sound ends.
        var waitToken: UInt64?
    }

    /// What adopting a started source asks of the engine.
    public struct Adoption: Equatable, Sendable {
        public let keeps: Bool
        public let volume: Float?
    }

    private var instances: [Int32: Instance] = [:]
    private var nextID: Int32 = 1

    public init() {}

    /// A new instance ID. 0 stays free: it means "failed to play".
    public mutating func begin(waitToken: UInt64? = nil) -> Int32 {
        let id = nextID
        nextID = nextID == .max ? 1 : nextID + 1
        instances[id] = Instance(waitToken: waitToken)
        return id
    }

    /// The engine started `id`'s source. A stopped instance does not keep it.
    public mutating func adopt(_ id: Int32, source: Int) -> Adoption {
        guard var instance = instances[id], !instance.stopped else {
            return Adoption(keeps: false, volume: nil)
        }
        instance.sourceID = source
        instances[id] = instance
        return Adoption(keeps: true, volume: instance.volume)
    }

    /// The source to stop now, if one plays. A later adoption is refused.
    public mutating func stop(_ id: Int32) -> Int? {
        guard var instance = instances[id] else { return nil }
        instance.stopped = true
        instances[id] = instance
        return instance.sourceID
    }

    /// Values outside 0 to 1 are clamped, as the wiki says. Returns the source to set now.
    public mutating func setVolume(_ id: Int32, _ volume: Float) -> Int? {
        guard var instance = instances[id], volume.isFinite else { return nil }
        instance.volume = simd_clamp(volume, 0, 1)
        instances[id] = instance
        return instance.sourceID
    }

    /// The volume a script set, for the readout.
    public func volume(of id: Int32) -> Float? {
        instances[id]?.volume
    }

    /// Drops the instances whose source ended or never came, and answers each
    /// `PlayAndWait`: true when the sound played to its end.
    /// - Parameters:
    ///   - playing: the engine sources that still play.
    ///   - failed: instances whose file could not load.
    public mutating func retire(playing: Set<Int>, failed: Set<Int32>) -> [UInt64: Bool] {
        var answers: [UInt64: Bool] = [:]
        for (id, instance) in instances {
            let ended = instance.sourceID.map { !playing.contains($0) } ?? false
            let failedToStart = failed.contains(id)
            guard ended || failedToStart || (instance.stopped && instance.sourceID == nil)
            else { continue }
            if let token = instance.waitToken {
                answers[token] = ended && !instance.stopped
            }
            instances[id] = nil
        }
        return answers
    }

    public var count: Int {
        instances.count
    }

    public var isEmpty: Bool {
        instances.isEmpty
    }
}
