public import OpenSkyFormatsESM
public import OpenSkyMenusInterface

/// What the world adapters use of `DialogueMenuController`.
public protocol DialogueMenuPort: AnyObject {
    associatedtype DialogueMenuModel: DialogueMenuModelPort
    func begin(with speaker: ReferenceKey)
    func close()
    var isOpen: Bool { get }
    var model: DialogueMenuModel { get }
    var snapshot: DialogueControlSnapshot { get }
    var speakerOrTarget: ReferenceKey? { get }
    func route(_ event: MenuInputEvent)
}
