// How damage moves a reference through the stages of its base form's `DEST` data. Pure:
// the natives and the hits store the result in the script state. Stage flags are from
// xEdit `wbDefinitionsTES5.pas` (`DSTD`). See docs/engine/papyrus-destruction.md.

import Foundation
import OpenSkyFormatsESM

nonisolated struct DestructionProgress: Equatable, Sendable {
    /// Damage taken since the last `ClearDestruction`.
    var damage: Float = 0
    /// The `DSTD` index of the stage reached, 0 while intact.
    var stage = 0
    var isDestroyed = false

    static let capDamage: UInt8 = 0x01
    static let disable: UInt8 = 0x02
    static let destroy: UInt8 = 0x04
    static let ignoreExternalDamage: UInt8 = 0x08

    /// The health share a stage is reached at.
    private static func threshold(_ stage: Destructible.Stage, health: Float) -> Float {
        health * Float(stage.healthPercent) / 100
    }

    /// How many stages, in record order, `damage` has reached.
    private static func reachedCount(damage: Float, data: Destructible) -> Int {
        let health = Float(data.health)
        var count = 0
        for stage in data.stages {
            guard health - damage <= threshold(stage, health: health) else { break }
            count += 1
        }
        return count
    }

    /// Adds `amount` of damage and returns the stages it passed, in record order. Forced
    /// damage, such as a script's, passes the Ignore External Damage flag; other damage
    /// does nothing in such a stage and stops before the next one.
    mutating func apply(
        damage amount: Float, to data: Destructible, forced: Bool = true
    ) -> [Destructible.Stage] {
        let health = Float(data.health)
        guard amount > 0, amount.isFinite, health > 0, !isDestroyed, damage < health else {
            return []
        }
        let start = Self.reachedCount(damage: damage, data: data)
        if !forced, start > 0, data.stages[start - 1].flags & Self.ignoreExternalDamage != 0 {
            return []
        }
        var newDamage = damage + amount
        var passed: [Destructible.Stage] = []
        for stage in data.stages.dropFirst(start) {
            let threshold = Self.threshold(stage, health: health)
            guard health - newDamage <= threshold else { break }
            if !forced, stage.flags & Self.ignoreExternalDamage != 0 {
                newDamage = min(newDamage, max(damage, health - threshold - Self.holdMargin))
                break
            }
            passed.append(stage)
            if stage.flags & Self.capDamage != 0 {
                newDamage = min(newDamage, health - threshold)
                break
            }
        }
        damage = min(newDamage, health)
        guard let last = passed.last else { return [] }
        stage = Int(last.index)
        if passed.contains(where: { $0.flags & Self.destroy != 0 }) {
            isDestroyed = true
        }
        return passed
    }

    /// Health kept above a stage that external damage may not reach.
    private static let holdMargin: Float = 0.001

    /// `SetDestroyed(true)` jumps to the last stage; false makes the object whole again.
    static func destroyed(_ isDestroyed: Bool, data: Destructible?) -> DestructionProgress {
        guard isDestroyed else { return DestructionProgress() }
        let last = data?.stages.map { Int($0.index) }.max() ?? 0
        let health = Float(data?.health ?? 0)
        return DestructionProgress(damage: health, stage: last, isDestroyed: true)
    }
}
