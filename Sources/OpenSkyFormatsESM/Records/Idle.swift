// IDLE idle animation, ANIO animated object, and IDLM idle marker. An IDLE
// names its parent and previous sibling, so the idle tree is rebuilt from
// links. Layout and sources: docs/formats/idle.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct IdleAnimation: Equatable, Sendable {
    /// DATA, 6 bytes. xEdit marks the block unused by the game.
    public struct Properties: Equatable, Sendable {
        public let loopMinimum: UInt8
        public let loopMaximum: UInt8
        /// 0x01 loose, 0x02 sequence, 0x04 no attacking.
        public let flags: UInt8
        public let animationGroupSection: UInt8
        public let replayDelay: UInt16
    }

    public let formID: FormID
    public let editorID: String?
    public let conditions: [Condition]
    /// DNAM, the behavior file, relative to `Data/meshes`.
    public let fileName: String?
    /// ENAM, the behavior-graph event the idle sends.
    public let animationEvent: String?
    /// ANAM first half: an IDLE or AACT. Nil for a root.
    public let parent: FormID?
    /// ANAM second half. Nil for a first child.
    public let previousSibling: FormID?
    public let properties: Properties?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "IDLE")
        formID = fields.formID
        editorID = fields.editorID()
        conditions = fields.conditions()
        fileName = fields.zstring("DNAM")
        animationEvent = fields.zstring("ENAM")
        let links = fields.read("ANAM") { try ($0.readFormID(), $0.readFormID()) }
        parent = links?.0.nonNull
        previousSibling = links?.1.nonNull
        properties = fields.read("DATA") {
            try Properties(
                loopMinimum: $0.readUInt8(), loopMaximum: $0.readUInt8(),
                flags: $0.readUInt8(), animationGroupSection: $0.readUInt8(),
                replayDelay: $0.readUInt16()
            )
        }
        skipped = fields.finish()
    }
}

nonisolated public struct AnimatedObject: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let model: ModelData?
    /// BNAM, the behavior event that unloads the object.
    public let unloadEvent: String?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "ANIO")
        formID = fields.formID
        editorID = fields.editorID()
        model = fields.model()
        unloadEvent = fields.zstring("BNAM")
        skipped = fields.finish()
    }
}

nonisolated public struct IdleMarker: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let bounds: ObjectBounds?
    /// IDLF: 0x01 run in sequence, 0x04 do once, 0x10 ignored by sandbox.
    public let flags: UInt8?
    /// IDLC, the authored count of `idles`.
    public let declaredIdleCount: UInt8?
    /// IDLT, in seconds.
    public let idleTimer: Float?
    /// IDLA, IDLE records in order.
    public let idles: [FormID]
    public let model: ModelData?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "IDLM")
        formID = fields.formID
        editorID = fields.editorID()
        bounds = fields.bounds()
        flags = fields.uint8("IDLF")
        declaredIdleCount = fields.uint8("IDLC")
        idleTimer = fields.float("IDLT")
        idles = fields.formIDArray("IDLA")
        model = fields.model()
        if let declaredIdleCount, Int(declaredIdleCount) != idles.count {
            fields.note(.mismatch("IDLC count differs from IDLA entries"))
        }
        skipped = fields.finish()
    }
}
