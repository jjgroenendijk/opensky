// The resident references, their interactions, and activation.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// The resident references, their interactions, and activation. Part of `CellStreamerPort`.
public protocol CellStreamerResidentsPort {
    associatedtype CellScene: CellScenePort
    func activate(_ target: InteractionTarget, offeringPerkChoices: Bool)
    func appearanceSkipReasons(forActor formID: FormID) -> [String]
    func interactionName(reference: FormID) -> String?
    func inventoryHolder(of key: ReferenceKey) -> InventoryHolder?
    func nearestActorEntry(to position: SIMD3<Float>) -> RuntimeReferenceEntry?
    func residentActorEntry(key: ReferenceKey) -> RuntimeReferenceEntry?
    func residentActorPlacement(key: ReferenceKey) -> ResidentActorPlacement?
    func residentInteraction(reference: FormID) -> PlacedInteraction?
    var residentInteractions: [PlacedInteraction] { get }
    func residentReferenceIndex() -> RuntimeReferenceIndex
    func residentScene(at location: CellSceneLocation) -> CellScene?
    func residentReferencePlaces(location: (CellLocationKey) -> ResolvedFormID?) -> ReferencePlaces
}

extension CellStreamerResidentsPort {
    public func activate(_ target: InteractionTarget) {
        activate(target, offeringPerkChoices: true)
    }
}
