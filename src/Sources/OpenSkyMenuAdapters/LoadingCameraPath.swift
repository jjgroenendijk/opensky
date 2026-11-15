// A loading screen's MOD2 camera path, read the way the game reads it: the
// `CameraPath` sequence moves the `CameraPathNode`, and the node's place sets the
// scene camera (docs/engine/loading-screens.md#camera).

public import OpenSkyFormatsMesh
import simd

nonisolated public struct LoadingCameraPath: Sendable {
    static let sequenceName = "CameraPath"
    static let nodeName = "CameraPathNode"

    let sequence: NIFSequence?
    let channel: NIFTransformChannel?
    /// The node's place when the sequence does not move it.
    let rest: SIMD3<Float>

    init(sequence: NIFSequence?, channel: NIFTransformChannel?, rest: SIMD3<Float>) {
        self.sequence = sequence
        self.channel = channel
        self.rest = rest
    }

    public init(file: NIFFile) throws {
        let sequence = try file.sequences().first { $0.name == Self.sequenceName }
        let channel = sequence?.tracks.lazy.compactMap { track -> NIFTransformChannel? in
            guard
                track.target == .node(Self.nodeName),
                case let .transform(channel) = track.channel else { return nil }
            return channel
        }.first
        let rest = (try? NIFCameraTrack(file: file))?.translation(at: 0) ?? .zero
        self.init(sequence: sequence, channel: channel, rest: rest)
    }

    /// The first pose is taken this long after the path starts.
    static let firstPoseSeconds: Float = 0.001

    /// The node's place `seconds` after the screen showed. The sequence's own cycle
    /// decides whether the path loops or holds its end.
    public func nodePosition(after seconds: Double) -> SIMD3<Float> {
        guard let sequence, let channel else { return rest }
        let time = sequence.keyTime(after: Float(seconds) + Self.firstPoseSeconds)
        return channel.translation(at: time) ?? rest
    }
}
