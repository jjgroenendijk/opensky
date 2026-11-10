// The port an `.ess` export reads the installed plugins through. The app answers it
// from its game data; tests pass a fake. See docs/engine/ess-export.md.

public import Foundation
public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
public import OpenSkyScriptingInterface

nonisolated public protocol ESSExportRecords {
    /// The plugins loaded now, in the load order OpenSky's form ids count in.
    var plugins: [ESSExportPlugin] { get }
    /// The record type of a form, such as `QUST`, or `ACHR` for a placed actor.
    func signature(of form: ResolvedFormID) -> String?
    func editorID(of form: ResolvedFormID) -> String?
    /// A `GLOB`, `WRLD`, or other indexed form by editor ID.
    func form(editorID: String, signature: String) -> ResolvedFormID?
    /// A placed reference's record flags, as its plugin stores them.
    func recordFlags(of reference: ResolvedFormID) -> UInt32?
    /// Where a placed reference sits: its interior cell, or its exterior worldspace.
    func placementSpace(of reference: ResolvedFormID) -> ResolvedFormID?
    /// What the reference holds before any change. `.ess` counts are changes to it.
    func baselineInventory(of reference: ReferenceKey) -> ReferenceInventoryState
    /// A compiled script's own variables and its parent, or nil when none is found.
    func script(named name: String) -> ESSExportScript?
}

nonisolated public struct ESSExportPlugin: Equatable, Sendable {
    let name: String
    /// An ESL-flagged plugin, which the game numbers in the light plugin list.
    let isLight: Bool

    init(name: String, isLight: Bool = false) {
        self.name = name
        self.isLight = isLight
    }
}

nonisolated public struct ESSExportScript: Equatable, Sendable {
    nonisolated struct Variable: Equatable, Sendable {
        let name: String
        let typeName: String
        /// The compiled initial value, which an instance holds until a script sets it.
        let initial: PapyrusValue

        init(name: String, typeName: String, initial: PapyrusValue) {
            self.name = name
            self.typeName = typeName
            self.initial = initial
        }

        /// Object and array variables hold VM handles, which OpenSky does not keep.
        var holdsHandle: Bool {
            switch PapyrusType(name: typeName) {
            case .object, .array: true
            case .none, .boolean, .integer, .float, .string: false
            }
        }
    }

    let name: String
    /// Empty for a script with no parent.
    let parent: String
    let variables: [Variable]
}

/// Header text the session knows and the snapshot does not.
nonisolated public struct ESSExportHeader: Equatable, Sendable {
    public let saveNumber: UInt32
    /// The date line the load menu shows.
    public let gameDate: String
    public let experienceForNextLevel: Float
    public let savedAt: Date

    public init(
        saveNumber: UInt32, gameDate: String, experienceForNextLevel: Float, savedAt: Date
    ) {
        self.saveNumber = saveNumber
        self.gameDate = gameDate
        self.experienceForNextLevel = experienceForNextLevel
        self.savedAt = savedAt
    }
}
