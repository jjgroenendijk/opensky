// The trap state: trap triggers in the loaded cells with
// their script states, the enable-parent chain of the selected one, and the live
// hazards. Plain values, so the app assembles them. See docs/engine/traps.md.

public import OpenSkyFormatsESM

/// One trap trigger or trap reference with a trap-family script.
nonisolated struct TrapTriggerRow: Equatable, Sendable {
    let key: ReferenceKey
    let name: String
    /// Each trap script with its current Papyrus state, such as `tripwire: Disarmed`.
    let scripts: [String]
    let occupants: Int
    let isEnabled: Bool
}

/// One step of an `XESP` chain, the selected reference first.
nonisolated struct TrapChainLink: Equatable, Sendable {
    let name: String
    let isEnabled: Bool
    let isOppositeOfParent: Bool
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

nonisolated struct TrapControlSnapshot: Equatable, Sendable {
    let isAvailable: Bool
    let triggers: [TrapTriggerRow]
    let selected: ReferenceKey?
    let chain: [TrapChainLink]
    let hazards: [TrapHazardRow]
    let hazardHits: Int
    let lastText: String

    static let unavailable = TrapControlSnapshot(
        isAvailable: false, triggers: [], selected: nil, chain: [], hazards: [], hazardHits: 0,
        lastText: "No scripts running."
    )
}

/// The section readout, kept here so a package test can pin it.
nonisolated enum TrapReadout {
    /// Rows past this many are counted, not listed.
    static let listedRows = 10

    static func text(for snapshot: TrapControlSnapshot) -> String {
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
