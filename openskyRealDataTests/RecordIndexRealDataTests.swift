// Env-gated cross-plugin index census over the user's read-only install.

import Foundation
@testable import opensky
import Testing

struct RecordIndexRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func indexesReferenceRecordFamiliesAcrossTheLoadOrder() throws {
        let root = try #require(Self.dataRoot)
        let started = DispatchTime.now().uptimeNanoseconds
        let index = RecordIndexLoader.load(root: root)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000

        let floors: [(type: FourCC, count: Int)] = [
            ("KYWD", 1260), ("FLST", 1034), ("LCTN", 829), ("LCRT", 481),
            ("ECZN", 358), ("AACT", 71), ("COLL", 55), ("DOBJ", 5)
        ]
        for floor in floors {
            #expect(
                index.collectedCount(of: floor.type) >= floor.count,
                "\(floor.type) fell below the five-master census floor"
            )
        }

        let actorTypeNPC = index.records.first { _, entry in
            entry.record.type == "KYWD" && ESMWalk.editorID(of: entry.record) == "ActorTypeNPC"
        }
        #expect(actorTypeNPC?.key == ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x13794))
        print("[INFO] eight-family RecordIndex built in \(elapsed) ms")
    }
}
