public import OpenSkyFormatsESM
public import OpenSkyMenusInterface

/// What the world adapters use of `MessageWorldAdapter`.
public protocol MessageWorldPort: AnyObject {
    func buildMessage(_ key: ReferenceKey, arguments: [Float]) -> BuiltMessage?
    var messageEditorIDs: [String] { get }
    func messageKey(editorID: String) -> ReferenceKey?
}
