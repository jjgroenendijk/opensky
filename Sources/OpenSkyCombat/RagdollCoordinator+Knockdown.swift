// A living actor knocked down: its ragdoll falls, it lies until it is still or its time is
// out, then it stands where its pelvis lies and the ragdoll pose fades into the get-up
// clip (docs/engine/ragdoll.md#knockdown).

import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyPhysics
import simd

extension RagdollCoordinator {
    /// The get-up blend when the graph runs no `hkbGetUpModifier`; OpenSky's value.
    public static let fallbackGetUpDuration: Float = 1
    static let pelvisBone = "NPC Pelvis [Pelv]"
    static let neckBone = "NPC Neck [Neck]"

    /// Knocks a living actor down: every body of its ragdoll takes `magnitude` Havok metres a
    /// second away from `source`, by `KnockdownPush.weight(ofBone:)`. It lies for at most
    /// `downTime` seconds. False when it cannot ragdoll.
    @discardableResult
    public func knockDown(
        _ key: ReferenceKey, from source: SIMD3<Float>, magnitude: Float, downTime: Float
    ) -> Bool {
        guard
            let runtime, isUp(key, runtime: runtime), magnitude.isFinite, magnitude != 0
        else { return false }
        let wasDown = knockdowns.isKnockedDown(key)
        let speed = magnitude * NIFCollisionModel.havokToEngineScale
        guard runtime.knock(key, awayFrom: source, speed: speed, weight: KnockdownPush.weight)
        else { return false }
        knockdowns.knockDown(key, downTime: downTime)
        if !wasDown {
            queuedKnockdownCommands.append(.enterKnockdown(key))
        }
        return true
    }

    func advanceKnockdowns(delta: Float, runtime: RagdollRuntime) -> [RagdollCommand] {
        var commands = queuedKnockdownCommands
        queuedKnockdownCommands = []
        for key in knockdowns.phases.keys.sorted()
            where !isUp(key, runtime: runtime) || !runtime.world.isRagdolling(key)
        {
            knockdowns.remove(key)
            commands.append(.endKnockdown(key))
        }
        let step = knockdowns.advance(
            by: delta,
            getUpDuration: { self.world.getUpDuration(of: $0) ?? Self.fallbackGetUpDuration },
            isStill: { runtime.world.instance(for: $0)?.isStillEnoughToGetUp ?? true }
        )
        for key in step.gettingUp {
            guard let instance = runtime.world.instance(for: key) else { continue }
            commands.append(Self.getUp(key, from: instance))
        }
        for key in step.stood {
            runtime.removeRagdoll(key)
            commands.append(.endKnockdown(key))
        }
        return commands
    }

    /// Alive and not kneeling in bleedout, so a knock can put it on the ground.
    private func isUp(_ key: ReferenceKey, runtime: RagdollRuntime) -> Bool {
        guard key == .player else { return !runtime.isDead(key) && !bleedout.contains(key) }
        return !playerDeath.isDead && !playerDeath.isBleedingOut
    }

    /// Where the actor stands to get up: over its pelvis, on its lowest body, facing from
    /// the pelvis to the neck.
    static func getUp(_ key: ReferenceKey, from instance: RagdollInstance) -> RagdollCommand {
        let pelvis = instance.position(ofBone: pelvisBone) ?? instance.restingRootPosition ?? .zero
        let ground = instance.lowestBodyHeight ?? pelvis.z
        let yaw = instance.position(ofBone: neckBone)
            .flatMap { KnockdownPush.getUpYaw(pelvis: pelvis, neck: $0) }
        return .getUp(key, feet: SIMD3(pelvis.x, pelvis.y, ground), yaw: yaw)
    }
}
