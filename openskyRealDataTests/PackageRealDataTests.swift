// Real-data acceptance for issue #201. Reads the user's Skyrim.esm in place;
// no bytes, dumps, or rendered game content leave the gitignored run output.

import Foundation
@testable import opensky
import Testing

struct PackageRealDataTests {
    private struct Resident {
        let name: String
        let base: UInt32
        let expected: [UInt32]
    }

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty else {
            return nil
        }
        return try? GameDataLocator.locate()
    }()

    private static let residents = [
        Resident(name: "Ysolda", base: 0x0001_3BAB, expected: [
            0x0002_C3BA, 0x0001_B210, 0x0001_B210, 0x0001_B210,
            0x0001_B210, 0x0001_B210, 0x0001_B210, 0x0001_B210,
            0x0002_C3B9, 0x0002_C3B9, 0x0002_C3B9, 0x0002_C3B9,
            0x0002_C3B9, 0x0002_C3B9, 0x0002_C3B9, 0x0003_1730,
            0x000C_E32E, 0x000C_E32E, 0x000C_E32E, 0x000C_E32E,
            0x0003_1730, 0x0002_C3BA, 0x0002_C3BA, 0x0002_C3BA
        ]),
        Resident(name: "Belethor", base: 0x0001_3BA1, expected: [
            0x0009_6107, 0x0009_6107, 0x0009_6107, 0x0009_6107,
            0x0009_6107, 0x0009_6107, 0x0009_6107, 0x0009_6107,
            0x0002_BE19, 0x0002_BE19, 0x0002_BE19, 0x0002_BE19,
            0x0002_BE19, 0x0002_BE19, 0x0002_BE19, 0x0002_BE19,
            0x0002_BE19, 0x0002_BE19, 0x0002_BE19, 0x0002_BE19,
            0x0002_BE1C, 0x0002_BE1C, 0x0002_BE1C, 0x0002_BE1C
        ]),
        Resident(
            name: "Hulda",
            base: 0x0001_3BA3,
            expected: Array(repeating: 0x0001_8959, count: 24)
        ),
        Resident(name: "Heimskr", base: 0x0001_3BAC, expected: [
            0x000E_73CA, 0x000E_73CA, 0x000E_73CA, 0x000E_73CA,
            0x000E_73CA, 0x0002_C3B7, 0x0002_C3B7, 0x0002_C3B7,
            0x0002_C3B7, 0x0002_C3B7, 0x0002_C3B7, 0x0002_C3B7,
            0x0002_C3B7, 0x0002_C3B7, 0x0002_C3B7, 0x0002_C3B7,
            0x0002_C3B7, 0x0002_C3B7, 0x0002_C3B7, 0x0002_C3B7,
            0x0002_C3B8, 0x0002_C3B8, 0x0002_C3B8, 0x0002_C3B8
        ])
    ]

    @Test(.enabled(if: Self.dataRoot != nil))
    func censusesReachablePackagesAndHeaderConditions() throws {
        let file = try skyrimFile()
        let store = PackageStore(file: file)
        var reachable: Set<FormID> = []
        for resident in Self.residents {
            let stack = try store.packageStack(for: FormID(resident.base)).value
            for package in stack {
                try reachable.formUnion(store.resolve(package).templateChain)
            }
        }
        #expect(reachable.count == 21)

        let records = try packageRecords(file)
        let fieldTypes = try Set(reachable.flatMap { package -> [String] in
            let record = try #require(records[package.rawValue])
            return try record.fields().map { String(describing: $0.type) }
        })
        #expect(fieldTypes == [
            "ANAM", "BNAM", "CIS2", "CITC", "CNAM", "CTDA", "EDID", "FNAM",
            "INAM", "PDTO", "PKC2", "PKCU", "PKDT", "PLDT", "PNAM", "POBA",
            "POCA", "POEA", "PRCB", "PSDT", "PTDA", "SCHR", "UNAM", "VMAD", "XNAM"
        ])

        let functionTally = Dictionary(grouping: reachable.flatMap { id in
            store.package(id)?.conditions.conditions.map(\.functionIndex) ?? []
        }, by: { $0 }).mapValues(\.count)
        #expect(functionTally == [35: 3, 606: 1, 629: 1])
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    func selectsFourResidentsAcrossAFullDay() throws {
        let file = try skyrimFile()
        let store = PackageStore(file: file)
        let references = try heimskrConditionReferences(file)
        for (offset, resident) in Self.residents.enumerated() {
            let actorKey = ReferenceKey.generated(UInt64(offset + 1))
            var runtime = ActorPackageRuntime(store: store)
            try runtime.register(actor: actorKey, base: FormID(resident.base))
            var observed: [UInt32] = []
            for hour in 0 ..< 24 {
                runtime.forceReevaluate(
                    actor: actorKey,
                    clock: GameClock(hour: Float(hour)),
                    context: ConditionContext(references: references)
                )
                let selected = try #require(runtime.currentPackage(for: actorKey))
                observed.append(selected.package.formID.rawValue)
            }
            #expect(observed == resident.expected, "full-day schedule for \(resident.name)")
        }
    }

    private func skyrimFile() throws -> ESMFile {
        let root = try #require(Self.dataRoot)
        return try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
    }

    private func packageRecords(_ file: ESMFile) throws -> [UInt32: ESMRecord] {
        let group = try #require(file.topGroup(of: "PACK"))
        return try Dictionary(uniqueKeysWithValues: group.children().compactMap { child in
            guard case let .record(record) = child, record.type == "PACK" else { return nil }
            return (record.formID, record)
        })
    }

    private func heimskrConditionReferences(_ file: ESMFile) throws -> RuntimeReferenceIndex {
        let rawFormID: UInt32 = 0x000F_C8F1
        let record = try #require(ESMWalk.record(withFormID: rawFormID, in: file))
        let reference = try PlacedReference(record: record)
        #expect(reference.isInitiallyDisabled)
        return RuntimeReferenceIndex(entries: [RuntimeReferenceEntry(
            key: .plugin(name: "skyrim.esm", objectID: FormID(rawFormID).objectID),
            formID: FormID(rawFormID),
            isPersistent: true,
            record: .reference(reference)
        )])
    }
}
