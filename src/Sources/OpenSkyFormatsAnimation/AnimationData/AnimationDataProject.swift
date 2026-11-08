// `meshes\animationdata\<project>.txt`: the project's behavior files and, per clip
// generator, its motion index, speed, crop, and triggers.
// Layout: docs/formats/animation-data.md.

import Foundation

nonisolated public struct AnimationDataTrigger: Equatable, Sendable {
    public let name: String
    public let time: Float

    public init(name: String, time: Float) {
        self.name = name
        self.time = time
    }
}

nonisolated public struct AnimationDataClip: Equatable, Sendable {
    /// The clip generator's name, as the behavior file spells it.
    public let name: String
    /// The block in the project's motion table.
    public let motionIndex: Int
    public let playbackSpeed: Float
    public let cropStart: Float
    public let cropEnd: Float
    public let triggers: [AnimationDataTrigger]
}

nonisolated public struct AnimationDataProject: Equatable, Sendable {
    public let behaviorFiles: [String]
    /// Keyed by the lowercased generator name.
    public let clips: [String: AnimationDataClip]

    public init(text: String) throws {
        var lines = AnimationDataLines(text)
        _ = try lines.integer("a leading number")
        let fileCount = try lines.count("the behavior file count")
        behaviorFiles = try (0 ..< fileCount).map { _ in try lines.text("a behavior file") }
        var clips: [String: AnimationDataClip] = [:]
        // A project without clip data, such as a creature with no root motion, ends here.
        if !lines.isAtEnd, try lines.integer("the clip data flag") != 0 {
            while !lines.isAtEnd {
                lines.skipBlank()
                let clip = try Self.clip(&lines)
                clips[clip.name.lowercased()] = clips[clip.name.lowercased()] ?? clip
            }
        }
        self.clips = clips
    }

    public func clip(named name: String) -> AnimationDataClip? {
        clips[name.lowercased()]
    }

    private static func clip(_ lines: inout AnimationDataLines) throws -> AnimationDataClip {
        let name = try lines.text("a clip generator name")
        let index = try lines.integer("a motion index")
        let speed = try lines.floats(1, "a playback speed")[0]
        let cropStart = try lines.floats(1, "a crop start")[0]
        let cropEnd = try lines.floats(1, "a crop end")[0]
        let triggerCount = try lines.count("a trigger count")
        let triggers = try (0 ..< triggerCount).map { _ in
            let line = try lines.text("a trigger")
            guard
                let colon = line.lastIndex(of: ":"),
                let time = Float(line[line.index(after: colon)...])
            else { throw AnimationDataError.malformed(line: lines.position, expected: "name:time") }
            return AnimationDataTrigger(name: String(line[..<colon]), time: time)
        }
        return AnimationDataClip(
            name: name, motionIndex: index, playbackSpeed: speed,
            cropStart: cropStart, cropEnd: cropEnd, triggers: triggers
        )
    }
}
