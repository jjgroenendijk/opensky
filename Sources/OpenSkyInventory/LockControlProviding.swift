// Main-app lock seam: the locks in the loaded cells, the selected one, the key
// override, and the last lockpicking session. AppKit-free. See docs/engine/locks.md.

import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldInterface

/// One lock in the loaded cells.
nonisolated public struct LockReadoutRow: Equatable, Sendable {
    public let reference: FormID
    public let name: String
    public let difficulty: String
    public let key: String
    public let isLocked: Bool

    public init(reference: FormID, name: String, difficulty: String, key: String, isLocked: Bool) {
        self.reference = reference
        self.name = name
        self.difficulty = difficulty
        self.key = key
        self.isLocked = isLocked
    }

    public var title: String {
        "\(name) (\(reference))"
    }
}

nonisolated public struct LockControlSnapshot: Equatable, Sendable {
    public let isAvailable: Bool
    public let locks: [LockReadoutRow]
    public let selected: FormID?
    public let carriesEveryKey: Bool
    public let lockpicks: Int32
    public let lastOutcome: LockpickingOutcome?
    public let lastText: String

    public static let unavailable = LockControlSnapshot(
        isAvailable: false, locks: [], selected: nil, carriesEveryKey: false, lockpicks: 0,
        lastOutcome: nil, lastText: "No item runtime."
    )

    public init(
        isAvailable: Bool,
        locks: [LockReadoutRow],
        selected: FormID?,
        carriesEveryKey: Bool,
        lockpicks: Int32,
        lastOutcome: LockpickingOutcome?,
        lastText: String
    ) {
        self.isAvailable = isAvailable
        self.locks = locks
        self.selected = selected
        self.carriesEveryKey = carriesEveryKey
        self.lockpicks = lockpicks
        self.lastOutcome = lastOutcome
        self.lastText = lastText
    }

    public var selectedRow: LockReadoutRow? {
        locks.first { $0.reference == selected }
    }
}

@MainActor
public protocol LockControlProviding: AnyObject {
    var lockSnapshot: LockControlSnapshot { get }
    func selectLock(_ reference: FormID?)
    @discardableResult
    func setSelectedLockLocked(_ locked: Bool) -> String
    func setPlayerCarriesEveryKey(_ enabled: Bool)
    /// Opens the lockpicking menu on the selected lock.
    @discardableResult
    func pickSelectedLock() -> String
}

extension LockCoordinator {
    public var lockSnapshot: LockControlSnapshot {
        guard items != nil else { return .unavailable }
        let rows = (world?.lockables() ?? []).compactMap(row).sorted {
            ($0.name, $0.reference.rawValue) < ($1.name, $1.reference.rawValue)
        }
        return LockControlSnapshot(
            isAvailable: true,
            locks: rows,
            selected: selectedLock,
            carriesEveryKey: playerCarriesEveryKey,
            lockpicks: lockpickCount,
            lastOutcome: lastOutcome,
            lastText: lastText
        )
    }

    /// The selected lock while its cell is loaded.
    public var selectedInteraction: PlacedInteraction? {
        guard let selectedLock else { return nil }
        return world?.lockables().first { $0.reference == selectedLock }
    }

    public func selectLock(_ reference: FormID?) {
        selectedLock = reference
    }

    @discardableResult
    public func setSelectedLockLocked(_ locked: Bool) -> String {
        guard let interaction = selectedInteraction else { return note("No lock selected.") }
        return setLocked(interaction, locked: locked)
    }

    public func setPlayerCarriesEveryKey(_ enabled: Bool) {
        playerCarriesEveryKey = enabled
        world?.lockStateChanged()
    }

    private func row(_ interaction: PlacedInteraction) -> LockReadoutRow? {
        guard let state = lock(of: interaction)?.state else { return nil }
        return LockReadoutRow(
            reference: interaction.reference,
            name: interaction.name,
            difficulty: state.difficulty.name,
            key: state.key.map { world?.itemName($0) ?? $0.description } ?? "none",
            isLocked: state.isLocked
        )
    }
}

/// The section readout, kept here so a package test can pin it.
nonisolated public enum LockReadout {
    /// Lock rows past this many are counted, not listed.
    public static let listedLocks = 10

    public static func text(for snapshot: LockControlSnapshot) -> String {
        guard snapshot.isAvailable else { return snapshot.lastText }
        let locked = snapshot.locks.count(where: \.isLocked)
        var lines = ["Locks: \(snapshot.locks.count), locked \(locked)"]
        lines += snapshot.locks.prefix(listedLocks).map { "  \(line($0))" }
        if snapshot.locks.count > listedLocks {
            lines.append("  and \(snapshot.locks.count - listedLocks) more")
        }
        lines += [
            "Selected: \(snapshot.selectedRow.map(line) ?? "none")",
            "Lockpicks: \(snapshot.lockpicks)",
            "Carries every key: \(snapshot.carriesEveryKey ? "yes" : "no")",
            "Last session: \(outcomeText(snapshot.lastOutcome))",
            "Last: \(snapshot.lastText)"
        ]
        return lines.joined(separator: "\n")
    }

    static func line(_ row: LockReadoutRow) -> String {
        "\(row.name): \(row.difficulty), key \(row.key), \(row.isLocked ? "locked" : "open")"
    }

    public static func outcomeText(_ outcome: LockpickingOutcome?) -> String {
        guard let outcome else { return "none" }
        let experience = (outcome.experience * 10).rounded() / 10
        return "\(outcome.opened ? "opened" : "left") \(outcome.difficulty.name), "
            + "picks broken \(outcome.picksBroken), XP \(experience)"
            + (outcome.keyRewarded ? ", key found" : "")
    }
}
