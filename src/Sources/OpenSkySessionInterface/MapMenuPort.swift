public import OpenSkyFormatsESM
public import OpenSkyMenusInterface

/// What the world adapters use of `MapMenuCoordinator`.
public protocol MapMenuPort: AnyObject {
    func addToMap(_ key: ReferenceKey, allowFastTravel: Bool)
    var camera: WorldMapCamera? { get }
    func canTravel(to key: ReferenceKey) -> Bool
    var fastTravelEnabled: Bool { get set }
    func isVisible(_ key: ReferenceKey) -> Bool
    var mode: MapMenuMode? { get }
    @discardableResult func open(_ requested: MapMenuMode, focus: SIMD3<Float>?) -> Bool
    func placePlayerMarker()
    func route(_ event: MenuInputEvent)
    @discardableResult func select(key: ReferenceKey) -> Bool
    @discardableResult func showQuestTarget(quest: FormID?, objective: UInt16?) -> Bool
    var snapshot: MapMenuSnapshot { get }
    func tick()
    func travelToSelected()
}

/// The default arguments a protocol requirement cannot carry.
extension MapMenuPort {
    @discardableResult public func showQuestTarget(objective: UInt16?) -> Bool {
        showQuestTarget(quest: nil, objective: objective)
    }

    @discardableResult public func showQuestTarget(quest: FormID?) -> Bool {
        showQuestTarget(quest: quest, objective: nil)
    }

    @discardableResult public func showQuestTarget() -> Bool {
        showQuestTarget(quest: nil, objective: nil)
    }

    @discardableResult public func open(focus: SIMD3<Float>?) -> Bool {
        open(.world, focus: focus)
    }

    @discardableResult public func open(_ requested: MapMenuMode) -> Bool {
        open(requested, focus: nil)
    }

    @discardableResult public func open() -> Bool {
        open(.world, focus: nil)
    }
}
