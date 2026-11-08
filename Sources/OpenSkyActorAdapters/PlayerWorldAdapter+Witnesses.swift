public import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
public import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySession
import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `PlayerWorldAdapter`.
extension PlayerWorldAdapter {
    public func showPlayerBody(_ body: PlayerBody) throws {
        try firstPerson.showPlayerBody(body)
    }

    public func showFirstPersonRig(_ rig: PlayerFirstPersonRig) throws {
        try firstPerson.showFirstPersonRig(rig)
    }

    public var playerFirstPersonRig: PlayerFirstPersonRig? {
        firstPerson.playerFirstPersonRig
    }

    public var areFirstPersonArmsVisible: Bool {
        firstPerson.areFirstPersonArmsVisible
    }

    public var firstPersonFOVYRadians: Float? {
        firstPerson.firstPersonFOVYRadians
    }

    public func setFirstPersonFOVY(radians: Float) {
        firstPerson.setFirstPersonFOVY(radians: radians)
    }

    public var firstPersonArmsEnabled: Bool? {
        firstPerson.firstPersonArmsEnabled
    }

    public func setFirstPersonArmsEnabled(_ enabled: Bool) {
        firstPerson.setFirstPersonArmsEnabled(enabled)
    }

    public var faceMorphSubject: FormID? {
        face.faceMorphSubject
    }

    public func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback? {
        face.faceMorphPlayback(for: actor)
    }

    public var faceMorphPlaybacks: [FaceMorphPlayback] {
        face.faceMorphPlaybacks
    }

    public func faceMood(of actor: FormID) -> FaceMoodInput {
        face.faceMood(of: actor)
    }

    public var headTrackingSubjects: [HeadTrackingSubject] {
        face.headTrackingSubjects
    }

    public func headPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        face.headPosition(of: key)
    }
}
