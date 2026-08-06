// hkbProjectStringData and hkbCharacterStringData decode (todo 14.1). These
// are the graph-level metadata that names the *other* files a behavior set
// pulls in: a project file lists its behavior, character, and animation
// directories, and a character file lists the animation clips its graph can
// play plus the behavior file it starts from. The census reports both, which
// is how the vanilla player behavior set is enumerated without guessing paths.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); both classes derive
// from hkReferencedObject, so the first member sits at 0x10. No Havok SDK or
// Bethesda code consulted (AGENTS.md Legal & IP). Byte map and citations:
// docs/formats/hkx-behavior.md.

import Foundation

/// Decoded `hkbProjectData` plus the `hkbProjectStringData` it points at. A
/// project file (`defaultmale.hkx`, `firstperson.hkx`) is the root of one
/// behavior set.
nonisolated struct HKBProjectData: Equatable {
    let animationFilenames: [String?]
    let behaviorFilenames: [String?]
    let characterFilenames: [String?]
    let eventNames: [String?]
    let animationPath: String?
    let behaviorPath: String?
    let characterPath: String?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbProjectData"
    static let stringDataClassName = "hkbProjectStringData"

    private static let stringDataField = HKXField(0x20, "m_stringData")
    private static let animationFilenamesField = HKXField(0x10, "m_animationFilenames")
    private static let behaviorFilenamesField = HKXField(0x20, "m_behaviorFilenames")
    private static let characterFilenamesField = HKXField(0x30, "m_characterFilenames")
    private static let eventNamesField = HKXField(0x40, "m_eventNames")
    private static let animationPathField = HKXField(0x50, "m_animationPath")
    private static let behaviorPathField = HKXField(0x58, "m_behaviorPath")
    private static let characterPathField = HKXField(0x60, "m_characterPath")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBProjectData?
    {
        guard var owner = graph.cursor(at: target) else { return nil }
        guard
            let stringData = owner.pointer(at: stringDataField),
            var cursor = graph.cursor(at: stringData)
        else {
            return HKBProjectData(
                animationFilenames: [], behaviorFilenames: [], characterFilenames: [],
                eventNames: [], animationPath: nil, behaviorPath: nil, characterPath: nil,
                unresolved: owner.unresolved
            )
        }
        return HKBProjectData(
            animationFilenames: cursor.stringArray(at: animationFilenamesField),
            behaviorFilenames: cursor.stringArray(at: behaviorFilenamesField),
            characterFilenames: cursor.stringArray(at: characterFilenamesField),
            eventNames: cursor.stringArray(at: eventNamesField),
            animationPath: cursor.string(at: animationPathField),
            behaviorPath: cursor.string(at: behaviorPathField),
            characterPath: cursor.string(at: characterPathField),
            unresolved: owner.unresolved + cursor.unresolved
        )
    }
}

/// Decoded `hkbCharacterData` plus the `hkbCharacterStringData` it points at.
/// A character file binds one behavior file to one rig and to the clip list
/// its graph may play.
nonisolated struct HKBCharacterData: Equatable {
    let name: String?
    let rigName: String?
    let ragdollName: String?
    let behaviorFilename: String?
    let animationNames: [String?]
    let characterPropertyNames: [String?]
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbCharacterData"
    static let stringDataClassName = "hkbCharacterStringData"

    private static let stringDataField = HKXField(0x98, "m_stringData")
    private static let animationNamesField = HKXField(0x30, "m_animationNames")
    private static let characterPropertyNamesField = HKXField(
        0x50, "m_characterPropertyNames"
    )
    private static let nameField = HKXField(0xA0, "m_name")
    private static let rigNameField = HKXField(0xA8, "m_rigName")
    private static let ragdollNameField = HKXField(0xB0, "m_ragdollName")
    private static let behaviorFilenameField = HKXField(0xB8, "m_behaviorFilename")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBCharacterData?
    {
        guard var owner = graph.cursor(at: target) else { return nil }
        guard
            let stringData = owner.pointer(at: stringDataField),
            var cursor = graph.cursor(at: stringData)
        else {
            return HKBCharacterData(
                name: nil, rigName: nil, ragdollName: nil, behaviorFilename: nil,
                animationNames: [], characterPropertyNames: [],
                unresolved: owner.unresolved
            )
        }
        return HKBCharacterData(
            name: cursor.string(at: nameField),
            rigName: cursor.string(at: rigNameField),
            ragdollName: cursor.string(at: ragdollNameField),
            behaviorFilename: cursor.string(at: behaviorFilenameField),
            animationNames: cursor.stringArray(at: animationNamesField),
            characterPropertyNames: cursor.stringArray(at: characterPropertyNamesField),
            unresolved: owner.unresolved + cursor.unresolved
        )
    }
}
