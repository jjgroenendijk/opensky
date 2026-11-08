public import OpenSkyMenusInterface

/// What the world adapters use of `SaveGameWorldAdapter`.
public protocol SaveGameWorldPort: AnyObject {
    func autosave(_ trigger: AutosaveTrigger)
    func quickload()
    func requestSave(autosave: Bool) -> Bool
    func resetPlayTime()
    var saveRows: [SaveSlotRow] { get }
}
