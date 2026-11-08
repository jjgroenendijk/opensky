public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
public import OpenSkyScriptingInterface

/// What the world adapters use of `InventoryWorldAdapter`.
public protocol InventoryWorldPort: AnyObject, PapyrusAlchemyBridge, PapyrusInventoryBridge {
    func dropPlacement() -> DropPlacement?
    func forgetPickpocketCatch(of key: ReferenceKey)
    func itemKeywords(of item: FormID) -> [FormID]?
    @discardableResult func run<Value>(_ result: InventoryResult<Value>) -> Value
    func setOutfit(_ outfit: FormID, on actor: ReferenceKey) -> Bool
    func settlePickpocketCatches(chargedTo faction: ReferenceKey, forgotten: Bool)
}
