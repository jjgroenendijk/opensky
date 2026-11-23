public import OpenSkyConditions
public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What the world adapters use of `CellScene`.
public protocol CellScenePort {
    associatedtype CellLoadSummary: CellLoadSummaryPort
    var doors: [PlacedDoor] { get }
    var encounterZone: FormID? { get }
    var interactions: [FormID: PlacedInteraction] { get }
    var forbidsWaiting: Bool { get }
    var isInterior: Bool { get }
    var location: CellSceneLocation? { get }
    var locationKey: CellLocationKey { get }
    var locationLink: FormID? { get }
    var owner: RecordOwnership? { get }
    var ownerPluginName: String? { get }
    var referenceCell: ReferenceCell? { get }
    var references: RuntimeReferenceIndex { get }
    var stateSequence: UInt64 { get }
    var summary: CellLoadSummary { get }
    var trespass: CellTrespassFlags { get set }
}
