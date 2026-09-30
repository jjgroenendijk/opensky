// `MeleeCombatControlProviding` conformance for the Melee section. Every field
// reads `MeleeCombatRuntime`. The controls use the same latches as the mouse and
// the R key, so the sidebar verifies the binding.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics

extension GameViewController: MeleeCombatControlProviding {
    var isWeaponDrawn: Bool {
        get { melee.runtime?.state.drawState.isWeaponInHand ?? false }
        set { melee.runtime?.setWeaponDrawn(newValue) }
    }

    var meleeCombatSnapshot: MeleeCombatSnapshot {
        guard let runtime = melee.runtime else { return .unavailable }
        let weapon = runtime.weapon
        return MeleeCombatSnapshot(
            isAvailable: true,
            drawState: runtime.state.drawState,
            attackPhase: runtime.state.attackPhase,
            isBlocking: runtime.state.isBlocking,
            isStaggering: runtime.state.isStaggering,
            weaponName: weaponName(weapon),
            weaponDamage: weapon.damage,
            weaponReachMultiplier: weapon.reach,
            weaponSpeed: weapon.speed,
            rightHandType: weapon.handType,
            leftHandType: runtime.offHand,
            reach: runtime.currentReach,
            swingCount: runtime.swingCount,
            hitCount: runtime.hitCount,
            trace: runtime.trace.map(readout),
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
    func requestMeleeAttack() -> String {
        guard let runtime = melee.runtime else {
            return Self.noMeleeText
        }
        guard runtime.state.drawState.canAttack else {
            melee.lastActionText =
                "Cannot attack: weapon is \(runtime.state.drawState.rawValue)."
            return melee.lastActionText
        }
        runtime.requestAttack()
        melee.lastActionText = "Requested one swing."
        return melee.lastActionText
    }

    func clearMeleeTrace() {
        melee.runtime?.clearTrace()
        melee.lastActionText = "Cleared the hit trace."
    }

    // MARK: - Private

    private static let noMeleeText = "Melee unavailable: no game data loaded."

    /// How the readout names the swinging weapon: its editor ID when the item
    /// index resolves one, else its FormID, else "unarmed".
    private func weaponName(_ profile: MeleeWeaponProfile) -> String {
        guard let id = profile.weapon else { return "unarmed" }
        return melee.weapons?.definition(id)?.editorID ?? id.description
    }

    private func readout(_ record: MeleeHitRecord) -> MeleeHitReadout {
        MeleeHitReadout(
            target: record.target.description,
            distance: record.distance,
            baseDamage: record.damage.base,
            blockedPercent: record.damage.blockedFraction * 100,
            appliedDamage: record.damage.applied,
            sound: record.sound?.description,
            staggered: record.staggered,
            enchantment: record.enchantment?.describedLine
        )
    }
}
