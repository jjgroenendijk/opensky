// `ArcheryControlProviding` conformance (issue #196, roadmap item 15.5, scope
// point 6): the live readouts and the four controls the
// `World > Player & Locomotion > Archery` section is written against.
//
// Every field is a plain read off `ArcheryRuntime` and `ProjectileRuntime`,
// with no accounting invented at the UI. The spawn control goes through the
// same `loose` the graph's `arrowRelease` goes through, so a shot taken from
// the sidebar is indistinguishable downstream from one the player took.

import Foundation

extension GameViewController: ArcheryControlProviding {
    var archerySnapshot: ArcherySnapshot {
        guard let runtime = archery.runtime else { return .unavailable }
        let projectiles = runtime.projectiles
        let arrow = runtime.arrow
        return ArcherySnapshot(
            isAvailable: true,
            phase: runtime.state.phase,
            hasArrowAttached: runtime.state.hasArrowAttached,
            heldSeconds: runtime.heldSeconds,
            lastHeldSeconds: runtime.lastHeldSeconds,
            drawFraction: ArcheryDamage.drawFraction(
                heldSeconds: runtime.heldSeconds, speed: runtime.bow.speed
            ),
            bowName: name(of: runtime.bow.weapon) ?? "none",
            bowDamage: runtime.bow.weapon == nil ? 0 : runtime.bow.damage,
            bowSpeed: runtime.bow.speed,
            arrowName: name(of: arrow?.item) ?? "none",
            arrowDamage: arrow?.damage ?? 0,
            projectileName: name(of: arrow?.profile.projectile) ?? "none",
            projectileSpeed: arrow?.profile.speed ?? 0,
            projectileGravityFactor: arrow?.profile.gravityFactor ?? 0,
            projectileRange: arrow?.profile.range ?? 0,
            drawRequestCount: runtime.drawRequestCount,
            firedCount: projectiles.firedCount,
            impactCount: projectiles.impactCount,
            liveCount: projectiles.live.count,
            stuckCount: projectiles.stuck.count,
            trace: projectiles.trace.map(readout),
            settings: runtime.settings.report.map { entry in
                String(
                    format: "%@ = %.3f [%@]",
                    entry.editorID,
                    entry.setting.value,
                    entry.setting.source
                )
            }
        )
    }

    @discardableResult
    func spawnDevProjectile() -> String {
        guard let runtime = archery.runtime else {
            return Self.noArcheryText
        }
        runtime.arrow = selectedArrow()
        guard runtime.arrow != nil else {
            archery.lastActionText = "Cannot fire: no ammunition with a flyable PROJ carried."
            return archery.lastActionText
        }
        guard let projectile = runtime.loose(consumesArrow: false) else {
            archery.lastActionText = "Cannot fire: the projectile has no launch speed."
            return archery.lastActionText
        }
        archery.lastActionText = String(
            format: "Fired projectile #%d at %.0f units/s.",
            projectile.id,
            simd_length(projectile.state.velocity)
        )
        return archery.lastActionText
    }

    func despawnProjectiles() {
        archery.runtime?.projectiles.despawnAll()
        archery.lastActionText = "Despawned everything in flight."
    }

    func clearStuckProjectiles() {
        archery.runtime?.projectiles.clearStuckArrows()
        archery.lastActionText = "Pulled every stuck arrow back out."
    }

    func clearProjectileTrace() {
        archery.runtime?.projectiles.clearTrace()
        archery.lastActionText = "Cleared the shot trace."
    }

    // MARK: - Private

    private static let noArcheryText = "Archery unavailable: no game data loaded."

    /// How the readout names a record: its editor ID when the item index
    /// resolves one, else its FormID. Nil for a nil link, which the caller
    /// turns into "none".
    private func name(of id: FormID?) -> String? {
        guard let id else { return nil }
        if let definition = archery.items?.definition(id) {
            return definition.editorID ?? id.description
        }
        return archery.items?.projectiles[id.rawValue]?.editorID ?? id.description
    }

    private func readout(_ trace: ProjectileTrace) -> ProjectileTraceReadout {
        ProjectileTraceReadout(
            id: trace.id,
            launch: trace.launchPosition,
            end: trace.endPosition,
            flightTime: trace.flightTime,
            travelled: trace.travelled,
            drop: trace.drop,
            outcome: trace.outcome,
            target: trace.target?.description,
            appliedDamage: trace.appliedDamage,
            sound: trace.sound?.description,
            stuck: trace.stuck
        )
    }
}
