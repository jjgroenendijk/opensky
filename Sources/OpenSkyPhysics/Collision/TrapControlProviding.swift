// The seam for World > World > Traps: the trap triggers in the loaded cells with
// their script states, the enable-parent chain of the selected one, and the live
// hazards. Plain values, so the app assembles them. See docs/engine/traps.md.

import OpenSkyFormatsESM

/// One trap trigger or trap reference with a trap-family script.
nonisolated public struct TrapTriggerRow: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String
    /// Each trap script with its current Papyrus state, such as `tripwire: Disarmed`.
    public let scripts: [String]
    public let occupants: Int
    public let isEnabled: Bool

    public init(
        key: ReferenceKey, name: String, scripts: [String], occupants: Int, isEnabled: Bool
    ) {
        self.key = key
        self.name = name
        self.scripts = scripts
        self.occupants = occupants
        self.isEnabled = isEnabled
    }
}

/// One step of an `XESP` chain, the selected reference first.
nonisolated public struct TrapChainLink: Equatable, Sendable {
    public let name: String
    public let isEnabled: Bool
    public let isOppositeOfParent: Bool

    public init(name: String, isEnabled: Bool, isOppositeOfParent: Bool) {
        self.name = name
        self.isEnabled = isEnabled
        self.isOppositeOfParent = isOppositeOfParent
    }
}

nonisolated public struct TrapHazardRow: Equatable, Sendable {
    public let name: String
    /// Seconds left for a spawned hazard; nil while a placed one lasts with its cell.
    public let remainingLifetime: Float?
    public let lastHitTargets: Int
    public let lastHitEffects: Int
    public let position: SIMD3<Float>
    /// Steps on which the hazard hit someone.
    public let tickCount: Int

    public init(
        name: String,
        remainingLifetime: Float?,
        lastHitTargets: Int,
        lastHitEffects: Int,
        position: SIMD3<Float> = .zero,
        tickCount: Int = 0
    ) {
        self.name = name
        self.remainingLifetime = remainingLifetime
        self.lastHitTargets = lastHitTargets
        self.lastHitEffects = lastHitEffects
        self.position = position
        self.tickCount = tickCount
    }
}

nonisolated public struct TrapControlSnapshot: Equatable, Sendable {
    public let isAvailable: Bool
    public let triggers: [TrapTriggerRow]
    public let selected: ReferenceKey?
    public let chain: [TrapChainLink]
    public let hazards: [TrapHazardRow]
    public let hazardHits: Int
    public let lastText: String

    public static let unavailable = TrapControlSnapshot(
        isAvailable: false, triggers: [], selected: nil, chain: [], hazards: [], hazardHits: 0,
        lastText: "No scripts running."
    )

    public init(
        isAvailable: Bool,
        triggers: [TrapTriggerRow],
        selected: ReferenceKey?,
        chain: [TrapChainLink],
        hazards: [TrapHazardRow],
        hazardHits: Int,
        lastText: String
    ) {
        self.isAvailable = isAvailable
        self.triggers = triggers
        self.selected = selected
        self.chain = chain
        self.hazards = hazards
        self.hazardHits = hazardHits
        self.lastText = lastText
    }
}

@MainActor
public protocol TrapControlProviding: AnyObject {
    var trapSnapshot: TrapControlSnapshot { get }
    func selectTrap(_ key: ReferenceKey?)
    /// The player steps into the selected trigger and out again.
    @discardableResult
    func fireSelectedTrap() -> String
    /// The player presses the use key on the selected trap.
    @discardableResult
    func disarmSelectedTrap() -> String
}

/// The section readout, kept here so a package test can pin it.
nonisolated public enum TrapReadout {
    /// Rows past this many are counted, not listed.
    public static let listedRows = 10

    public static func text(for snapshot: TrapControlSnapshot) -> String {
        guard snapshot.isAvailable else { return snapshot.lastText }
        var lines = ["Traps: \(snapshot.triggers.count)"]
        lines += listed(snapshot.triggers.map(line))
        let selected = snapshot.triggers.first { $0.key == snapshot.selected }
        lines.append("Selected: \(selected.map(line) ?? "none")")
        if !snapshot.chain.isEmpty {
            lines.append("Enable chain: " + snapshot.chain.map(link).joined(separator: " <- "))
        }
        lines.append("Hazards: \(snapshot.hazards.count), hits \(snapshot.hazardHits)")
        lines += listed(snapshot.hazards.map(line))
        lines.append("Last: \(snapshot.lastText)")
        return lines.joined(separator: "\n")
    }

    static func line(_ row: TrapTriggerRow) -> String {
        let state = row.scripts.isEmpty ? "no script" : row.scripts.joined(separator: ", ")
        return "\(row.name): \(state), inside \(row.occupants)"
            + (row.isEnabled ? "" : ", disabled")
    }

    static func line(_ row: TrapHazardRow) -> String {
        let lifetime = row.remainingLifetime.map { "\(($0 * 10).rounded() / 10) s left" }
            ?? "stays with cell"
        let hit = row.lastHitTargets == 0 ? "no hit yet"
            : "last hit \(row.lastHitTargets) actors, \(row.lastHitEffects) effects"
        let ticks = row.tickCount == 0 ? "" : ", \(row.tickCount) ticks"
        return "\(row.name): \(lifetime), \(hit)\(ticks)"
    }

    static func link(_ link: TrapChainLink) -> String {
        "\(link.name) \(link.isEnabled ? "on" : "off")" +
            (link.isOppositeOfParent ? " (opposite)" : "")
    }

    private static func listed(_ lines: [String]) -> [String] {
        var shown = lines.prefix(listedRows).map { "  \($0)" }
        if lines.count > listedRows {
            shown.append("  and \(lines.count - listedRows) more")
        }
        return shown
    }
}
