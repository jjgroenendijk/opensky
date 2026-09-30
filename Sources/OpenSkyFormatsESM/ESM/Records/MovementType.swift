// MOVT record decoded into engine types: a movement type and its directional
// speeds. The player's gaits are four MOVT records, so locomotion reads their
// forward speeds instead of inventing multipliers. SPED is 11 floats in xEdit's
// order; forward sits at indices 4 and 5. Layout: docs/formats/records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct MovementType: Equatable, Sendable {
    /// The SPED struct: eight directional speeds in units per second followed
    /// by three rotation speeds in radians per second. Every slot is kept even
    /// where the bridge reads only the forward pair, because dropping fields at
    /// decode time is how a later consumer ends up re-parsing the record.
    public struct Speeds: Equatable, Sendable {
        public let leftWalk: Float
        public let leftRun: Float
        public let rightWalk: Float
        public let rightRun: Float
        public let forwardWalk: Float
        public let forwardRun: Float
        public let backWalk: Float
        public let backRun: Float
        public let rotateInPlaceWalk: Float
        public let rotateInPlaceRun: Float
        public let rotateWhileMovingRun: Float

        /// The 11 floats in file order, for round-trip tests and reporting.
        public var values: [Float] {
            [
                leftWalk, leftRun, rightWalk, rightRun,
                forwardWalk, forwardRun, backWalk, backRun,
                rotateInPlaceWalk, rotateInPlaceRun, rotateWhileMovingRun
            ]
        }

        public static let floatCount = 11

        /// Decodes SPED, or nil when the field is short. A truncated struct is
        /// dropped whole rather than zero-padded: a half-read speed would read
        /// as a legitimate "this actor cannot move".
        public init?(field data: Data) {
            var reader = BinaryReader(data)
            var floats: [Float] = []
            floats.reserveCapacity(Self.floatCount)
            for _ in 0 ..< Self.floatCount {
                guard let value = try? reader.readFloat32(), value.isFinite else { return nil }
                floats.append(value)
            }
            self.init(values: floats)
        }

        /// Builds from 11 file-order floats; nil for any other count.
        public init?(values: [Float]) {
            guard values.count == Self.floatCount else { return nil }
            leftWalk = values[0]
            leftRun = values[1]
            rightWalk = values[2]
            rightRun = values[3]
            forwardWalk = values[4]
            forwardRun = values[5]
            backWalk = values[6]
            backRun = values[7]
            rotateInPlaceWalk = values[8]
            rotateInPlaceRun = values[9]
            rotateWhileMovingRun = values[10]
        }
    }

    public let formID: FormID
    public let editorID: String?
    /// MNAM — the name the behavior graph and the Creation Kit show. Distinct
    /// from EDID in vanilla (`NPC_Sneaking_MT` is named `NPCSneaking`).
    public let name: String?
    /// SPED. Nil when the record carries none or carries a truncated one.
    public let speeds: Speeds?

    public init(record: ESMRecord) throws {
        guard record.type == "MOVT" else {
            throw ESMError.malformed("expected MOVT record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var name: String?
        var speeds: Speeds?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "MNAM":
                name = try reader.readZString()
            case "SPED":
                speeds = Speeds(field: field.data)
            default:
                // INAM is a float triple of directional-change thresholds that
                // nothing in the engine reads yet, and is skipped rather than
                // guessed at.
                break
            }
        }
        self.editorID = editorID
        self.name = name
        self.speeds = speeds
    }
}

/// MOVT records across the load order, keyed by editor ID. Later plugins win,
/// as with GMSTs. Lookup is case-insensitive, like every editor-ID lookup.
nonisolated public struct MovementTypeStore: Equatable, Sendable {
    public private(set) var types: [String: MovementType] = [:]
    public private(set) var skippedRecords = SkippedRecords()

    public static let empty = MovementTypeStore(types: [:])

    private init(types: [String: MovementType]) {
        self.types = types
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        for plugin in plugins {
            add(file: plugin.file)
        }
    }

    public func type(editorID: String) -> MovementType? {
        types[editorID.lowercased()]
    }

    /// The forward speeds of one movement type, or nil when the record or its
    /// SPED is missing.
    public func forwardSpeeds(editorID: String) -> (walk: Float, run: Float)? {
        guard let speeds = type(editorID: editorID)?.speeds else { return nil }
        return (speeds.forwardWalk, speeds.forwardRun)
    }

    /// Editor IDs of the player gaits OpenSky reads, as vanilla names them.
    public enum PlayerGait: Sendable {
        public static let sneaking = "NPC_Sneaking_MT"
        public static let sprinting = "NPC_Sprinting_MT"
        public static let swimming = "NPC_Swimming_MT"
    }

    private mutating func add(file: ESMFile) {
        let decoded = file.decodeRecords(of: "MOVT", skipped: &skippedRecords) {
            try MovementType(record: $0)
        }
        for type in decoded {
            if let editorID = type.editorID {
                types[editorID.lowercased()] = type
            }
        }
    }
}
