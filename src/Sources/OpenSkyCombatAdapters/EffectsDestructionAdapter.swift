// What a destruction stage does in the world: it swaps the model, keeps damaging the
// object each second, and for each stage passed throws debris and sets off the
// explosion. See docs/engine/papyrus-destruction.md#in-the-game.

import Foundation
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorldState
import simd

/// What `EffectsDestructionAdapter` reads from the session.
@MainActor
public protocol EffectsDestructionHost: AnyObject, SendableMetatype {
    var combat: any CombatPort { get }
    var scripts: any ScriptPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// The objects a stage left burning, and the time toward their next tick.
public struct DestructionBurns {
    /// Damage per second for each object a stage keeps damaging.
    public var perSecond: [ReferenceKey: Float] = [:]
    var clock: Float = 0
    /// Moves each stage explosion inside its object's bounds.
    let random = RandomStream(seed: StageBlastPlacement.seed)

    public init() {}
}

/// Part of `EffectsWorldAdapter`, over its own narrow host.
public struct EffectsDestructionAdapter {
    /// The debris pieces fly out as from a small blast.
    static let debrisForce: Float = 100

    public let game: any EffectsDestructionHost

    public init(game: any EffectsDestructionHost) {
        self.game = game
    }

    /// Applies the stages the last hits passed, then a second of damage over time.
    public func step(_ seconds: Float, burns: inout DestructionBurns) {
        guard let bridge = game.scripts.bridge else { return }
        for change in bridge.takeDestructionChanges() {
            apply(change, through: bridge, burns: &burns)
        }
        guard !burns.perSecond.isEmpty else { return }
        burns.clock += seconds.isFinite ? max(seconds, 0) : 0
        while burns.clock >= 1 {
            burns.clock -= 1
            for (key, damage) in burns.perSecond.sorted(by: { $0.key < $1.key }) {
                let stillBurns = bridge.destructionHealthLeft(of: key).map { $0 > 0 } ?? false
                guard stillBurns else {
                    burns.perSecond[key] = nil
                    continue
                }
                bridge.damageDestructible(key, amount: damage, forced: true)
            }
        }
    }

    private func apply(
        _ change: DestructionStageChange,
        through bridge: some PapyrusWorldStateBridgePort,
        burns: inout DestructionBurns
    ) {
        let key = change.reference
        if let last = change.stages.last {
            // A stage with its own model swaps to it; otherwise the mesh shows the stage.
            let model = change.stages.last(where: { $0.model != nil })?.model
                ?? game.worldState.component(ReferenceDamageModel.self, for: key)?.path
            game.worldState.set(
                ReferenceDamageModel(
                    path: model,
                    stage: last.model == nil ? last.modelDamageStage : nil
                ),
                for: key
            )
        }
        if let last = change.stages.last {
            burns.perSecond[key] = last.selfDamagePerSecond > 0 ? last.selfDamagePerSecond : nil
        }
        guard let transform = bridge.referenceState(for: key)?.transform else { return }
        let explosions = game.combat.explosions
        let position = transform.position
        for stage in change.stages {
            if let debris = stage.debris, stage.debrisCount > 0 {
                explosions.throwDebris(
                    debris, at: position, force: Self.debrisForce, count: stage.debrisCount
                )
            }
            if let explosion = stage.explosion, let spec = explosions.spec(for: explosion) {
                let centre = StageBlastPlacement.position(
                    origin: position, bounds: (change.boundsCentre, change.boundRadius),
                    heading: transform.rotation.z, random: { burns.random.float(in: 0 ..< 1) }
                )
                explosions.detonate(
                    spec, at: centre, cause: .script, origin: ExplosionOrigin(owner: key)
                )
            }
        }
    }
}
