public import OpenSkyActorPresentation
import OpenSkyAIPackages
public import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `IdleWorldAdapter`.
extension IdleWorldAdapter {
    public func idleReferencePlacements() -> [IdleReferencePlacement]? {
        placement.idleReferencePlacements()
    }

    public func idleActors() -> [IdleActorPresence] {
        placement.idleActors()
    }

    public var idleAnimationTime: Float? {
        placement.idleAnimationTime
    }

    public func turnActor(
        _ actor: ReferenceKey, toHeading heading: Float, within tolerance: Float
    ) -> Float? {
        placement.turnActor(actor, toHeading: heading, within: tolerance)
    }

    public func setProp(_ prop: ActorPropAttachment?, on actor: ReferenceKey) {
        placement.setProp(prop, on: actor)
    }

    public func pairedActorPose(of actor: ReferenceKey) -> PairedActorPose? {
        placement.pairedActorPose(of: actor)
    }

    public func placePairedActor(_ actor: ReferenceKey, at pose: PairedActorPose) {
        placement.placePairedActor(actor, at: pose)
    }

    public func synchronizedMark(of actor: ReferenceKey) -> BehaviorSynchronizedMark? {
        placement.synchronizedMark(of: actor)
    }

    public func raiseIdleEvent(_ name: String, state: String?, on actor: ReferenceKey) -> Bool {
        placement.raiseIdleEvent(name, state: state, on: actor)
    }
}
