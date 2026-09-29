// hkbProjectStringData and hkbCharacterStringData decode: the other files a
// behavior set pulls in, so the census finds them without guessing paths.
// Offsets from HKX2Library (MIT). Byte map: docs/formats/hkx-behavior.md.

import Foundation

/// Decoded `hkbProjectData` plus the `hkbProjectStringData` it points at. A
/// project file (`defaultmale.hkx`, `firstperson.hkx`) is the root of one
/// behavior set.
nonisolated public struct HKBProjectData: Equatable, Sendable {
    public let animationFilenames: [String?]
    public let behaviorFilenames: [String?]
    public let characterFilenames: [String?]
    public let eventNames: [String?]
    public let animationPath: String?
    public let behaviorPath: String?
    public let characterPath: String?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbProjectData"

    private static let stringDataField = HKXField(0x20, "m_stringData")
    private static let animationFilenamesField = HKXField(0x10, "m_animationFilenames")
    private static let behaviorFilenamesField = HKXField(0x20, "m_behaviorFilenames")
    private static let characterFilenamesField = HKXField(0x30, "m_characterFilenames")
    private static let eventNamesField = HKXField(0x40, "m_eventNames")
    private static let animationPathField = HKXField(0x50, "m_animationPath")
    private static let behaviorPathField = HKXField(0x58, "m_behaviorPath")
    private static let characterPathField = HKXField(0x60, "m_characterPath")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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
nonisolated public struct HKBCharacterData: Equatable, Sendable {
    public let name: String?
    public let rigName: String?
    public let ragdollName: String?
    public let behaviorFilename: String?
    public let animationNames: [String?]
    public let characterPropertyNames: [String?]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbCharacterData"

    private static let stringDataField = HKXField(0x98, "m_stringData")
    private static let animationNamesField = HKXField(0x30, "m_animationNames")
    private static let characterPropertyNamesField = HKXField(
        0x50, "m_characterPropertyNames"
    )
    private static let nameField = HKXField(0xA0, "m_name")
    private static let rigNameField = HKXField(0xA8, "m_rigName")
    private static let ragdollNameField = HKXField(0xB0, "m_ragdollName")
    private static let behaviorFilenameField = HKXField(0xB8, "m_behaviorFilename")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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
