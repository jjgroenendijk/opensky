// Synthetic inputs for the condition-evaluator tests: CTDA field bytes, a
// globals resolution, and a reference index. Built in code, never extracted
// from game data (AGENTS.md "Legal & IP boundary").
//
// Conditions are always built as real 32-byte CTDA payloads and decoded through
// `Condition(ctda:)`, so every evaluator test also exercises the on-disk path
// rather than a hand-made value that could drift from the layout.

import Foundation
@testable import opensky

enum ConditionEvaluatorFixture {
    /// A well-formed 32-byte CTDA field. `operatorBits` are the top 3 bits of
    /// the operator byte and `flags` the low 5.
    static func field(
        operatorBits: UInt8 = 0,
        flags: UInt8 = 0,
        comparisonValue: UInt32 = 0,
        functionIndex: UInt16 = 0,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        runOn: UInt32 = 0,
        reference: UInt32 = 0,
        parameter3: Int32 = -1
    ) -> ESMField {
        var data = Data([(operatorBits << 5) | (flags & 0x1F), 0, 0, 0])
        data.appendUInt32(comparisonValue)
        data.appendUInt16(functionIndex)
        data.appendUInt16(0) // padding
        data.appendUInt32(parameter1)
        data.appendUInt32(parameter2)
        data.appendUInt32(runOn)
        data.appendUInt32(reference)
        data.appendUInt32(UInt32(bitPattern: parameter3))
        return ESMField(type: "CTDA", data: data)
    }

    /// The same payload, decoded. Throws only if the fixture itself is broken.
    static func condition(
        operatorBits: UInt8 = 0,
        flags: UInt8 = 0,
        comparisonValue: UInt32 = 0,
        functionIndex: UInt16 = 0,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        runOn: UInt32 = 0,
        reference: UInt32 = 0
    ) throws -> Condition {
        let payload = field(
            operatorBits: operatorBits,
            flags: flags,
            comparisonValue: comparisonValue,
            functionIndex: functionIndex,
            parameter1: parameter1,
            parameter2: parameter2,
            runOn: runOn,
            reference: reference
        )
        guard let condition = try Condition(ctda: payload) else {
            throw ESMError.malformed("fixture CTDA did not decode")
        }
        return condition
    }

    /// Condition comparing a function's return against a float literal.
    static func comparing(
        functionIndex: UInt16,
        _ comparison: UInt8,
        _ value: Float,
        runOn: UInt32 = 0,
        parameter1: UInt32 = 0
    ) throws -> Condition {
        try condition(
            operatorBits: comparison,
            comparisonValue: value.bitPattern,
            functionIndex: functionIndex,
            parameter1: parameter1,
            runOn: runOn
        )
    }

    // MARK: - Shared world state

    /// One synthetic float GLOB.
    struct GlobalSpec {
        let formID: UInt32
        let editorID: String
        let value: Float
    }

    /// GLOB the shared context defines: `OpenSkyTestFlag` is 1.
    static let flagFormID: UInt32 = 0x0000_0100
    /// `OpenSkyTestHalf` is 0.5.
    static let halfFormID: UInt32 = 0x0000_0101
    static let subjectFormID: UInt32 = 0x0001_0000
    static let targetFormID: UInt32 = 0x0001_0001
    static let subjectBase: UInt32 = 0x0002_0000
    static let targetBase: UInt32 = 0x0002_0001

    /// Globals resolution over synthetic float GLOB records.
    static func globals(_ specs: [GlobalSpec], clock: GameClock? = nil) throws -> GlobalResolution {
        var records = Data()
        for spec in specs {
            records += GlobalFixture.record(
                formID: spec.formID,
                editorID: spec.editorID,
                type: .float,
                value: spec.value
            )
        }
        return try GlobalResolution(defaults: GlobalFixture.store(records), clock: clock)
    }

    /// The two globals every condition test reads.
    static func standardGlobals() throws -> GlobalResolution {
        try globals([
            GlobalSpec(formID: flagFormID, editorID: "OpenSkyTestFlag", value: 1),
            GlobalSpec(formID: halfFormID, editorID: "OpenSkyTestHalf", value: 0.5)
        ])
    }

    /// Context with the standard globals, a placed subject and a placed target.
    static func populatedContext(clock: GameClock? = nil) throws -> ConditionContext {
        try ConditionContext(
            globals: standardGlobals(),
            clock: clock,
            references: references([
                (formID: subjectFormID, base: subjectBase),
                (formID: targetFormID, base: targetBase)
            ]),
            subject: key(subjectFormID),
            target: key(targetFormID)
        )
    }

    /// Evaluator over `populatedContext(clock:)`.
    static func evaluator(
        clock: GameClock? = nil,
        tally: ConditionTally = ConditionTally()
    ) throws -> ConditionEvaluator {
        try ConditionEvaluator(context: populatedContext(clock: clock), tally: tally)
    }

    /// `GetIsID(base) == 1` under `runOn`. The condition's own reference word
    /// points at the subject placement, which is what run-on 2 reads.
    static func isID(_ base: UInt32, runOn: UInt32 = 0, flags: UInt8 = 0) throws -> Condition {
        try condition(
            operatorBits: 0,
            flags: flags,
            comparisonValue: Float(1).bitPattern,
            functionIndex: 72,
            parameter1: base,
            runOn: runOn,
            reference: subjectFormID
        )
    }

    /// Reference index holding one REFR per `(formID, base)` pair, keyed the way
    /// a `skyrim.esm` placement would be.
    static func references(
        _ entries: [(formID: UInt32, base: UInt32)],
        plugin: String = "skyrim.esm"
    ) throws -> RuntimeReferenceIndex {
        try RuntimeReferenceIndex(entries: entries.map { entry in
            let id = FormID(entry.formID)
            return try RuntimeReferenceEntry(
                key: key(entry.formID, plugin: plugin),
                formID: id,
                isPersistent: false,
                record: .reference(placedReference(formID: entry.formID, base: entry.base))
            )
        })
    }

    static func key(_ formID: UInt32, plugin: String = "skyrim.esm") -> ReferenceKey {
        .plugin(name: plugin, objectID: FormID(formID).objectID)
    }

    private static func placedReference(formID: UInt32, base: UInt32) throws -> PlacedReference {
        var name = Data()
        name.appendUInt32(base)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
        let bytes = ESMFixture.record("REFR", formID: formID, data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return try PlacedReference(record: record)
    }
}
