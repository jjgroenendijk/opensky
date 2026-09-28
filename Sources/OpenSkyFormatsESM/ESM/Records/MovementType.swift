// MOVT record decoded into engine types: one named movement type and the
// directional walk/run speeds an actor using it moves at.
//
// A MOVT is how Skyrim states "how fast does an actor go while sneaking", which
// is what the locomotion bridge (issue #188) needs and what no GMST answers:
// `fMoveCharWalkBase` and `fMoveCharRunBase` describe the default gait only.
// The player's four gaits are four records — `NPC_Default_MT`,
// `NPC_Sneaking_MT`, `NPC_Sprinting_MT`, `NPC_Swimming_MT` — so the bridge
// reads their forward speeds rather than inventing multipliers.
//
// SPED is a fixed 11-float struct. The order is the one xEdit names and the
// shipped data corroborates: `NPC_Sprinting_MT` is 0 in every lateral slot and
// 500 in the forward pair, which is only consistent with forward sitting at
// float indices 4 and 5.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/MOVT"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MOVT
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbRecord(MOVT, ...)`
//     https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
// Layout + observed vanilla values documented in docs/formats/records.md.

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

    /// Synthetic movement type, for tests and for defaults assembled without a
    /// plugin.
    public init(formID: FormID, editorID: String?, name: String? = nil, speeds: Speeds?) {
        self.formID = formID
        self.editorID = editorID
        self.name = name
        self.speeds = speeds
    }
}

/// Immutable index of the MOVT records across the active load order, keyed by
/// editor ID. Later plugins win, which is the same override rule
/// `GameSettingStore` applies to GMSTs.
///
/// Editor-ID lookup is case-insensitive for the same reason the global index
/// is: the names travel through data files and console commands, where Skyrim
/// has never cared about case.
nonisolated public struct MovementTypeStore: Equatable, Sendable {
    public private(set) var types: [String: MovementType] = [:]

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

    /// Editor IDs of the four gaits the player uses, as vanilla names them.
    public enum PlayerGait: Sendable {
        public static let normal = "NPC_Default_MT"
        public static let sneaking = "NPC_Sneaking_MT"
        public static let sprinting = "NPC_Sprinting_MT"
        public static let swimming = "NPC_Swimming_MT"
    }

    private mutating func add(file: ESMFile) {
        guard
            let group = file.topGroup(of: "MOVT"),
            let children = try? group.children()
        else { return }
        for case let .record(record) in children where !record.isDeleted {
            guard
                let decoded = try? MovementType(record: record),
                let editorID = decoded.editorID
            else { continue }
            types[editorID.lowercased()] = decoded
        }
    }
}
