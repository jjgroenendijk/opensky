public import OpenSkyFormatsESM

/// What the world adapters use of `DialogueMenuModel`.
public protocol DialogueMenuModelPort {
    var speakerKey: ReferenceKey? { get }
}
