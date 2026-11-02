// The lock change forms of one save beside the plugin's XLOC: one observation per
// leveled lock of (player level, authored level, stored level). See docs/engine/locks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsESS

nonisolated public struct ESSLockRow: Equatable, Sendable {
    public let reference: ESSFormResolution
    public let storedLevel: UInt8
    public let storedFlags: UInt8
    public let key: ESSFormResolution
    /// Nil when the plugin's reference has no XLOC or is not loaded.
    public let authored: LockData?
}

nonisolated public struct ESSLeveledLockPair: Hashable, Comparable, Sendable {
    public let authored: UInt8
    public let stored: UInt8

    public init(authored: UInt8, stored: UInt8) {
        self.authored = authored
        self.stored = stored
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.authored, lhs.stored) < (rhs.authored, rhs.stored)
    }
}

nonisolated public struct ESSLockSurvey: Equatable, Sendable {
    public let playerLevel: UInt32
    public let rows: [ESSLockRow]

    public init(
        file: ESSFile, mapping: ESSLoadOrderMapping, authored: (ResolvedFormID) -> LockData?
    ) {
        playerLevel = file.header.playerLevel
        rows = file.changeForms.compactMap { change in
            guard
                change.type?.isReference == true,
                change.has(ESSChangeFlag.Object.extraLock),
                let decoded = try? ESSReferenceChange(change),
                case let .lock(level, flags, key)? = decoded.extraData?.entries
                    .first(where: { $0.type == 42 })
            else { return nil }
            let reference = mapping.resolve(change.form)
            var lock: LockData?
            if case let .form(form) = reference {
                lock = authored(form)
            }
            return ESSLockRow(
                reference: reference, storedLevel: level, storedFlags: flags,
                key: mapping.resolve(key), authored: lock
            )
        }
    }

    /// Leveled locks by (authored level, stored level), with how often each pair occurs.
    public var leveledPairs: [ESSLeveledLockPair: Int] {
        var counts: [ESSLeveledLockPair: Int] = [:]
        for row in rows {
            guard let lock = row.authored, lock.isLeveled else { continue }
            let pair = ESSLeveledLockPair(authored: lock.level.rawValue, stored: row.storedLevel)
            counts[pair, default: 0] += 1
        }
        return counts
    }

    public var lines: [String] {
        var lines = ["player level \(playerLevel), \(rows.count) lock change forms"]
        lines.append("reference\tstored\tflags\tkey\tauthored\tauthored flags")
        for row in rows {
            let authored = row.authored.map {
                "\($0.level.rawValue)\t0x\(String($0.flags, radix: 16))"
            } ?? "-\t-"
            let stored = "\(row.storedLevel)\t0x\(String(row.storedFlags, radix: 16))"
            lines.append(
                "\(Self.name(row.reference))\t\(stored)\t\(Self.name(row.key))\t\(authored)"
            )
        }
        lines.append("== Leveled locks: authored -> stored (count)")
        lines += leveledPairs.sorted { $0.key < $1.key }
            .map { "\($0.key.authored) -> \($0.key.stored) (\($0.value))" }
        return lines
    }

    private static func name(_ resolution: ESSFormResolution) -> String {
        switch resolution {
        case .null: "-"
        case let .form(form): "\(form.plugin):\(String(form.objectID, radix: 16))"
        case let .created(id): "created:\(String(id, radix: 16))"
        case let .unmapped(reason): "[\(reason.description)]"
        }
    }
}
