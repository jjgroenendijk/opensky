// Every `XLOC` lock in Skyrim.esm: the levels it uses, whether each key resolves
// to a `KEYM`, and the use-key gate on a real keyed lock. Counts go to `.logs/`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import Testing

struct LockRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyLockHasAKnownLevelAndAResolvableKey() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let types = ESMWalk.recordTypeIndex(in: file)
        var levels: [LockDifficulty: Int] = [:]
        var keyed: [LockData] = []
        var unknownLevels = 0
        var danglingKeys = 0
        ESMWalk.forEachRecord(in: file) { record in
            guard
                record.type == "REFR",
                let lock = (try? PlacedReference(record: record))?.lock
            else { return true }
            if case .unknown = lock.level {
                unknownLevels += 1
            }
            let state = ReferenceLockState(
                isLocked: true,
                level: lock.level.rawValue,
                key: lock.key
            )
            levels[state.difficulty, default: 0] += 1
            if let key = lock.key {
                keyed.append(lock)
                if types[key.rawValue] != "KEYM" {
                    danglingKeys += 1
                }
            }
            return true
        }
        let total = levels.values.reduce(0, +)
        #expect(total > 1000)
        #expect(keyed.count > 100)
        #expect(danglingKeys == 0)
        #expect(LockDifficulty.allCases.allSatisfy { levels[$0, default: 0] > 0 })
        try checkGate(on: #require(keyed.first))
        try write([
            "locks\t\(total)",
            "keyed\t\(keyed.count)",
            "dangling keys\t\(danglingKeys)",
            "unknown levels\t\(unknownLevels)"
        ] + LockDifficulty.allCases.map { "\($0.name)\t\(levels[$0, default: 0])" })
    }

    /// The door stays shut without its key and opens with it.
    private func checkGate(on lock: LockData) throws {
        let state = try #require(ReferenceLockState(baseline: lock))
        let key = try #require(lock.key)
        #expect(LockCore.decide(lock: state, carriesKey: false)
            == .refuse(.locked(level: state.level, key: key)))
        #expect(LockCore.decide(lock: state, carriesKey: true) == .unlockWithKey(key))
    }

    private func write(_ lines: [String]) throws {
        let directory = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(
            to: directory.appending(path: "lock-census.log"), atomically: true, encoding: .utf8
        )
    }
}
