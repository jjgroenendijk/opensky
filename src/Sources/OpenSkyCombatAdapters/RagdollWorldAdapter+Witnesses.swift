import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// Witnesses that forward to the narrow parts of `RagdollWorldAdapter`.
extension RagdollWorldAdapter {
    public func zeroHealthOutcome(
        of key: ReferenceKey,
        killer: ReferenceKey?
    ) -> ZeroHealthOutcome {
        recovery.zeroHealthOutcome(of: key, killer: killer)
    }

    public func healthFraction(of key: ReferenceKey) -> Float? {
        recovery.healthFraction(of: key)
    }

    public func bleedoutThreshold(of key: ReferenceKey) -> Float? {
        recovery.bleedoutThreshold(of: key)
    }

    public func blocksBleedoutRecovery(of key: ReferenceKey) -> Bool {
        recovery.blocksBleedoutRecovery(of: key)
    }

    public func restoreHealthShare(_ share: Float, of key: ReferenceKey) {
        recovery.restoreHealthShare(share, of: key)
    }

    public func getUpDuration(of key: ReferenceKey) -> Float? {
        recovery.getUpDuration(of: key)
    }

    public func dropWeapon(of key: ReferenceKey) -> Bool {
        remains.dropWeapon(of: key)
    }

    public func severableNode(of key: ReferenceKey) -> String? {
        remains.severableNode(of: key)
    }

    public func showDismemberment(of key: ReferenceKey, node: String, at position: SIMD3<Float>) {
        remains.showDismemberment(of: key, node: node, at: position)
    }

    public func isCorpseKept(_ key: ReferenceKey) -> Bool {
        remains.isCorpseKept(key)
    }

    public func removeCorpse(_ key: ReferenceKey) {
        remains.removeCorpse(key)
    }

    public var ragdollResidents: [RagdollResident] {
        poseReads.ragdollResidents
    }

    public var residentRagdollCells: Set<CellSceneLocation> {
        poseReads.residentRagdollCells
    }

    public func hasZeroHealth(_ key: ReferenceKey) -> Bool {
        poseReads.hasZeroHealth(key)
    }

    public func holder(of key: ReferenceKey) -> ActorValueHolder? {
        poseReads.holder(of: key)
    }

    public func ragdollPose(of key: ReferenceKey) -> RagdollActorPose? {
        poseReads.ragdollPose(of: key)
    }

    public func animatedPose(of key: ReferenceKey) -> [String: float4x4]? {
        poseReads.animatedPose(of: key)
    }

    public func raisePlayerGraphEvent(_ name: String) -> Bool {
        poseReads.raisePlayerGraphEvent(name)
    }

    public var ragdollStepWorld: DynamicStepWorld {
        poseReads.ragdollStepWorld
    }

    public func unloadedActorHome(of key: ReferenceKey) -> CellSceneLocation? {
        poseReads.unloadedActorHome(of: key)
    }

    public func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        deaths.queueActorDeathEvents(for: key, killer: killer)
    }

    public var selectedRagdollActor: ReferenceKey? {
        deaths.selectedRagdollActor
    }

    public var playerFeetPosition: SIMD3<Float>? {
        deaths.playerFeetPosition
    }

    public func searchCorpse(_ key: ReferenceKey) -> Bool {
        deaths.searchCorpse(key)
    }
}
