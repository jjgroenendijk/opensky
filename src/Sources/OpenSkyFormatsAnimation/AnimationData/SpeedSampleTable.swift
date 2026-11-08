// `meshes\speeddatasinglefile.txt`: for each behaviour project, the blend speed a
// graph's speed sampler gives for an actor's real ground speed, per state and
// direction. Layout: docs/formats/speed-data.md.

public import Foundation
import OpenSkyFormatsCore

nonisolated public enum SpeedSampleError: Error, Equatable, Sendable {
    case malformedHeader
    case unsupportedVersion(Int32)
    /// Over this many entries is not a speed file; a corrupt count would allocate forever.
    case implausibleCount(Int32)
}

/// One project's tables: state, then direction, then (ground speed, blend speed) pairs.
nonisolated public struct SpeedSampleProject: Equatable, Sendable {
    public struct Direction: Equatable, Sendable {
        public let key: Float
        /// Sorted by ground speed, as the file stores them.
        public let pairs: [(ground: Float, blend: Float)]

        public init(key: Float, pairs: [(ground: Float, blend: Float)]) {
            self.key = key
            self.pairs = pairs
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.key == rhs.key && lhs.pairs.elementsEqual(rhs.pairs) { $0 == $1 }
        }
    }

    public let states: [Int32: [Direction]]

    public init(states: [Int32: [Direction]]) {
        self.states = states
    }

    /// The blend speed for `goal`, or nil where no table answers, so the caller keeps
    /// `goal`. The direction is the first key at or above the input; past the last
    /// key it wraps to the first. Past the last ground speed the goal passes through.
    public func blendSpeed(state: Int32, direction: Float, goal: Float) -> Float? {
        guard let directions = states[state], let first = directions.first else { return nil }
        let table = directions.first { $0.key >= direction } ?? first
        guard let above = table.pairs.firstIndex(where: { $0.ground >= goal }) else {
            return table.pairs.isEmpty ? nil : goal
        }
        let end = table.pairs[above]
        let start = above > 0 ? table.pairs[above - 1] : (ground: Float(0), blend: Float(0))
        let span = end.ground - start.ground
        guard span > 0 else { return end.blend }
        return start.blend + (goal - start.ground) / span * (end.blend - start.blend)
    }
}

nonisolated public struct SpeedSampleTable: Equatable, Sendable {
    /// Keyed by the project's file name in lower case, without folder or extension:
    /// `DefaultMaleData\DefaultMale.spd` is `defaultmale`.
    public let projects: [String: SpeedSampleProject]

    private static let countLimit: Int32 = 100_000

    public init(data: Data) throws {
        var reader = BinaryReader(data)
        guard let count = try Int(Self.line(&reader)), count >= 0 else {
            throw SpeedSampleError.malformedHeader
        }
        let names = try (0 ..< count).map { _ in try Self.line(&reader) }
        var projects: [String: SpeedSampleProject] = [:]
        for name in names {
            projects[Self.key(forFile: name)] = try Self.project(&reader)
        }
        self.projects = projects
    }

    /// `meshes\actors\character\defaultmale.hkx` and `DefaultMale.spd` share a key.
    public static func key(forFile path: String) -> String {
        let file = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init)
            ?? path
        let stem = file.split(separator: ".").first.map(String.init) ?? file
        return stem.lowercased()
    }

    public func project(forBehaviorPath path: String) -> SpeedSampleProject? {
        projects[Self.key(forFile: path)]
    }

    private static func line(_ reader: inout BinaryReader) throws -> String {
        var bytes: [UInt8] = []
        while true {
            let byte = try reader.readUInt8()
            if byte == 0x0A {
                break
            }
            if byte != 0x0D {
                bytes.append(byte)
            }
        }
        guard let line = String(bytes: bytes, encoding: .utf8) else {
            throw SpeedSampleError.malformedHeader
        }
        return line
    }

    private static func count(_ reader: inout BinaryReader) throws -> Int {
        let value = try Int32(bitPattern: reader.readUInt32())
        guard value >= 0, value <= countLimit else {
            throw SpeedSampleError.implausibleCount(value)
        }
        return Int(value)
    }

    private static func project(_ reader: inout BinaryReader) throws -> SpeedSampleProject {
        let version = try Int32(bitPattern: reader.readUInt32())
        guard version == 1 else { throw SpeedSampleError.unsupportedVersion(version) }
        var states: [Int32: [SpeedSampleProject.Direction]] = [:]
        for _ in try 0 ..< count(&reader) {
            let state = try Int32(bitPattern: reader.readUInt32())
            states[state] = try (0 ..< count(&reader)).map { _ in
                let key = try reader.readFloat32()
                let pairs = try (0 ..< count(&reader)).map { _ in
                    // Stored blend first, then ground speed.
                    let blend = try reader.readFloat32()
                    return try (ground: reader.readFloat32(), blend: blend)
                }
                return SpeedSampleProject.Direction(key: key, pairs: pairs)
            }
        }
        return SpeedSampleProject(states: states)
    }
}
