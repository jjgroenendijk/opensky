// How damage moves a reference through the stages of its base form's `DEST` data. Pure:
// the natives store the result in the script state. Stage flags are from xEdit
// `wbDefinitionsTES5.pas` (`DSTD`). See docs/engine/papyrus-destruction.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct DestructionProgress: Equatable, Sendable {
    /// Damage taken since the last `ClearDestruction`.
    public var damage: Float = 0
    /// The `DSTD` index of the stage reached, 0 while intact.
    public var stage = 0
    public var isDestroyed = false

    public init(damage: Float = 0, stage: Int = 0, isDestroyed: Bool = false) {
        self.damage = damage
        self.stage = stage
        self.isDestroyed = isDestroyed
    }

    static let capDamage: UInt8 = 0x01
    static let disable: UInt8 = 0x02
    static let destroy: UInt8 = 0x04

    /// The stage passed when health falls to its percent, in the order health falls.
    private static func stages(of data: Destructible) -> [Destructible.Stage] {
        data.stages.sorted { $0.healthPercent > $1.healthPercent }
    }

    /// Adds `amount` of damage. A stage with the cap flag holds health at its percent,
    /// so later damage stops there. True in the result when the reached stage disables.
    public mutating func apply(damage amount: Float, to data: Destructible) -> Bool {
        guard amount > 0, amount.isFinite, data.health > 0, !isDestroyed else { return false }
        let health = Float(data.health)
        var newDamage = damage + amount
        var reached: Destructible.Stage?
        for stage in Self.stages(of: data) {
            let threshold = health * Float(stage.healthPercent) / 100
            guard health - newDamage <= threshold else { break }
            reached = stage
            if stage.flags & Self.capDamage != 0 {
                newDamage = min(newDamage, health - threshold)
                break
            }
        }
        damage = newDamage
        guard let reached else { return false }
        stage = max(stage, Int(reached.index))
        if reached.flags & Self.destroy != 0 {
            isDestroyed = true
        }
        return reached.flags & Self.disable != 0
    }

    /// `SetDestroyed(true)` jumps to the last stage; false makes the object whole again.
    public static func destroyed(_ isDestroyed: Bool, data: Destructible?) -> DestructionProgress {
        guard isDestroyed else { return DestructionProgress() }
        let last = data?.stages.map { Int($0.index) }.max() ?? 0
        let health = Float(data?.health ?? 0)
        return DestructionProgress(damage: health, stage: last, isDestroyed: true)
    }
}
