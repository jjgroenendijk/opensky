// Env-gated XPRM sweep over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP): walks every REFR in
// Skyrim.esm, tallies the on-disk shape of every primitive-volume subrecord,
// and pins the numbers `PlacedReference.decodePrimitive` relies on. Skips
// automatically when OPENSKY_DATA_ROOT is unset (CI has no game data).
//
// The counts are asserted rather than only written to logs/, because print()
// never reaches the .xcresult and a number nobody checks is not evidence. The
// tally holds counters and small bounded sets only; nothing accumulates a
// per-record object, so the sweep stays flat in memory over 693k references.
//
// Layout under test: UESP "Skyrim Mod:Mod File Format/REFR" XPRM row ("32 byte
// struct: float[3] x,y,z Bounds / 2; float[3] r,g,b Color / 255; float
// unknown; uint32 unknown: 1-4 seen") and xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas line 9701 `wbStruct(XPRM, 'Primitive',
// [wbStruct('Bounds', ...), wbFloatRGBA, wbInteger('Type', itU32,
// wbEnum(['None', 'Box', 'Sphere', 'Portal Box', 'Line']))])`.

import Foundation
@testable import opensky
import Testing

struct PlacedReferenceXPRMRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryPrimitiveVolumeInSkyrimESM() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let tally = Self.sweep(file: file)

        try? FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true
        )
        try? tally.summary.write(to: logURL, atomically: true, encoding: .utf8)

        check(tally)
    }

    // MARK: - Assertions

    /// Observed 2026-07-31 over Skyrim.esm (form version 44): 13668 XPRM
    /// subrecords, exactly one per carrying REFR, all 32 bytes, types box
    /// 10163, sphere 137, portal box 3135, line 233. Volume counts are
    /// asserted as lower bounds so a differently patched Skyrim.esm still
    /// passes, while the structural facts the parser depends on are pinned
    /// exactly.
    private func check(_ tally: Tally) {
        #expect(tally.references > 690_000, "REFR count far below the observed 693333")
        #expect(tally.referencesWithPrimitive > 13000, "XPRM carriers far below the observed 13668")
        #expect(tally.fields == tally.referencesWithPrimitive, "a REFR carried two XPRM fields")

        // Exact-size decode is only defensible because one size exists.
        #expect(Set(tally.sizeHistogram.keys) == [32], "unexpected XPRM payload size")
        #expect(tally.decodeFailures == 0, "a vanilla XPRM payload failed to decode")
        #expect(tally.decodedPrimitives == tally.referencesWithPrimitive)

        // Throwing on an out-of-enum type is only safe because vanilla uses
        // none. All four named shapes appear; the 'None' value 0 never does.
        #expect(tally.unknownTypes.isEmpty, "XPRM type outside xEdit's 0...4 enum")
        #expect(
            Set(tally.typeHistogram.keys) == [1, 2, 3, 4],
            "XPRM type set moved off box/sphere/portalBox/line"
        )
        #expect(tally.typeHistogram[0] == nil, "XPRM used the 'None' type value 0")
        #expect(
            tally.typeHistogram[1, default: 0] > 10000,
            "box count far below the observed 10163"
        )

        // Half-extents are a size, so they are finite and never negative; a
        // negative or NaN extent would mean the field order is wrong.
        #expect(tally.nonFiniteExtents == 0, "XPRM half-extent was NaN or infinite")
        #expect(tally.negativeExtents == 0, "XPRM half-extent was negative")

        // A zero axis is legal and vanilla uses it (129 axes observed), so a
        // decoder that rejected degenerate extents would drop real volumes.
        #expect(tally.zeroExtents > 0, "no zero XPRM half-extent axis, contradicting the doc")

        // Sphere radius source: every sphere primitive stores one value in all
        // three half-extent axes, so `halfExtents.x` is the radius and no axis
        // choice is being guessed. `CellTriggerBuilder` reads it that way.
        #expect(tally.spheres > 100, "sphere count far below the observed 137")
        #expect(
            tally.sphereAxisMismatches == 0,
            "a sphere XPRM stored unequal half-extent axes, so .x is not the radius"
        )

        // Color is stored 0...1, not 0...255: every channel of every payload
        // is in range, which is what makes UESP's "Color / 255" a display
        // note rather than an on-disk scale.
        #expect(tally.colorsOutsideUnitRange == 0, "XPRM color channel outside 0...1")

        // The fourth float is a small constant per base object rather than a
        // free value; the distinct set is exactly the four values UESP lists,
        // which is the strongest independent check that the field order is
        // right. It is carried verbatim rather than interpreted.
        #expect(
            tally.unknownValues == Set([0.15, 0.2, 0.25, 1.0].map { Float($0).bitPattern }),
            "the XPRM unknown float moved off UESP's 0.15/0.2/0.25/1.0"
        )
    }

    // MARK: - Sweep

    private struct Tally {
        var references = 0
        var referencesWithPrimitive = 0
        var decodedPrimitives = 0
        var decodeFailures = 0
        var unreadableReferences = 0
        var fields = 0
        var sizeHistogram: [Int: Int] = [:]
        var typeHistogram: [UInt32: Int] = [:]
        var unknownTypes: Set<UInt32> = []
        var nonFiniteExtents = 0
        var negativeExtents = 0
        var zeroExtents = 0
        var colorsOutsideUnitRange = 0
        var unknownValues: Set<UInt32> = []
        var largestExtent: Float = 0
        var spheres = 0
        /// Sphere primitives whose three half-extent axes are not all equal.
        var sphereAxisMismatches = 0

        var summary: String {
            let sizes = sizeHistogram.sorted { $0.key < $1.key }
                .map { "\($0.key)B:\($0.value)" }.joined(separator: " ")
            let types = typeHistogram.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }.joined(separator: " ")
            let unknowns = unknownValues.sorted()
                .map { "\(Float(bitPattern: $0))" }.joined(separator: " ")
            return """
            [INFO] Skyrim.esm XPRM sweep: \(fields) subrecords over \
            \(referencesWithPrimitive)/\(references) REFR records
            [INFO] payload sizes: \(sizes)
            [INFO] type histogram: \(types); outside the enum: \(unknownTypes.sorted())
            [INFO] half-extents: non-finite \(nonFiniteExtents), negative \(negativeExtents), \
            zero \(zeroExtents), largest \(largestExtent)
            [INFO] spheres: \(spheres), with unequal half-extent axes: \(sphereAxisMismatches)
            [INFO] color channels outside 0...1: \(colorsOutsideUnitRange)
            [INFO] distinct unknown floats (\(unknownValues.count)): \(unknowns)
            [INFO] decoded primitives \(decodedPrimitives), decode failures \(decodeFailures), \
            unreadable REFR records: \(unreadableReferences)
            """
        }
    }

    private static func sweep(file: ESMFile) -> Tally {
        var tally = Tally()
        ESMWalk.forEachRecord(in: file) { record in
            if record.type == "REFR" {
                accumulate(record: record, into: &tally)
            }
            return true
        }
        return tally
    }

    private static func accumulate(record: ESMRecord, into tally: inout Tally) {
        tally.references += 1
        guard let fields = try? record.fields() else {
            tally.unreadableReferences += 1
            return
        }
        let payloads = fields.filter { $0.type == "XPRM" }.map(\.data)
        guard !payloads.isEmpty else { return }
        tally.referencesWithPrimitive += 1
        tally.fields += payloads.count
        for payload in payloads {
            classify(payload: payload, into: &tally)
        }
        compare(record: record, into: &tally)
    }

    /// Reads the payload independently of the production decoder, so the
    /// sweep can see values the decoder would reject outright.
    private static func classify(payload: Data, into tally: inout Tally) {
        tally.sizeHistogram[payload.count, default: 0] += 1
        var reader = BinaryReader(payload)
        guard
            payload.count == 32, let floats = try? (0 ..< 7).map({ _ in
                try Float(bitPattern: reader.readUInt32())
            }), let rawType = try? reader.readUInt32() else { return }
        for extent in floats.prefix(3) {
            if !extent.isFinite {
                tally.nonFiniteExtents += 1
            } else if extent < 0 {
                tally.negativeExtents += 1
            } else if extent == 0 {
                tally.zeroExtents += 1
            }
            tally.largestExtent = max(tally.largestExtent, extent.isFinite ? extent : 0)
        }
        for channel in floats[3 ..< 6] where !(0 ... 1).contains(channel) {
            tally.colorsOutsideUnitRange += 1
        }
        tally.unknownValues.insert(floats[6].bitPattern)
        tally.typeHistogram[rawType, default: 0] += 1
        if PlacedReference.PrimitiveType(rawValue: rawType) == nil {
            tally.unknownTypes.insert(rawType)
        }
        // A sphere has one radius but three stored axes, and neither UESP nor
        // xEdit names which axis holds it. Counting the disagreements answers
        // it from the data: if no vanilla sphere disagrees, every axis carries
        // the radius and reading `halfExtents.x` is unambiguous (issue #173).
        if rawType == PlacedReference.PrimitiveType.sphere.rawValue {
            tally.spheres += 1
            if floats[0] != floats[1] || floats[1] != floats[2] {
                tally.sphereAxisMismatches += 1
            }
        }
    }

    /// Re-decodes the record through the production parser so the sweep proves
    /// what ships, not a second implementation of the same layout.
    private static func compare(record: ESMRecord, into tally: inout Tally) {
        guard let reference = try? PlacedReference(record: record) else {
            tally.decodeFailures += 1
            return
        }
        if reference.primitive == nil {
            tally.decodeFailures += 1
        } else {
            tally.decodedPrimitives += 1
        }
    }

    // MARK: - Artifacts

    private var logURL: URL {
        logsDirectory.appending(path: "xprm-sweep.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }
}
