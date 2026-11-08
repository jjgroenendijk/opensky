public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMenusInterface
public import OpenSkyWorldInterface

/// What the world adapters use of `MapWorldAdapter`.
public protocol MapWorldPort: AnyObject {
    func mapMarkerSites() -> [MapMarkerSite]
    var mapViewPose: CinematicCameraPose? { get }
    var questTargets: [QuestTargetMarker] { get }
    var records: MenuRecordData? { get }
    func settingTexts<Key: GameSettingTextKey>(_: Key.Type) -> GameSettingTexts<Key>
    func text(_ value: LString?, kind: StringTable.Kind) -> String?
    func text(_ setting: ResolvedGameText) -> String?
    func travel(to marker: MapMarkerSite) -> Bool
}

extension MapWorldPort {
    /// The key type comes from the caller's expected result.
    public func settingTexts<Key: GameSettingTextKey>() -> GameSettingTexts<Key> {
        settingTexts(Key.self)
    }
}

/// The default arguments a protocol requirement cannot carry.
extension MapWorldPort {
    public func text(_ value: LString?) -> String? {
        text(value, kind: .strings)
    }
}
